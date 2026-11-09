# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'open3'

module OSSBenchmark
  TRACERS = {
    'testsift' => { gem: 'testsift', config: '.testsift', constant: 'TestSift',
                    outputs: %w[testsift_cache testsift_report testsift_coverage] },
    'rspec-tracer' => { gem: 'rspec-tracer', config: '.rspec-tracer', constant: 'RSpecTracer',
                        outputs: %w[rspec_tracer_cache rspec_tracer_report rspec_tracer_coverage] }
  }.freeze
  RSPEC_TRACER_VERSION = '2.0.0.rc.1'
  RUBY_ROOTS = ['~/.local/share/rv/rubies/ruby-%s', '~/.rubies/ruby-%s', '/opt/rubies/ruby-%s',
                '~/.rbenv/versions/%s', '~/.asdf/installs/ruby/%s', '~/.local/share/mise/installs/ruby/%s'].freeze
  STRIPPED_ENV = %w[RUBYOPT RUBYLIB CI COVERAGE TEST_ENV_NUMBER PARALLEL_TEST_GROUPS
                    PARALLEL_TEST_PROCESSORS].freeze

  class SetupError < StandardError; end

  # One project checkout outside the TestSift source tree, pinned to the
  # manifest commit. Benchmark-owned files are excluded from Git, so a clean
  # `git status` proves the tracked tree matches the pin before each sample.
  class Workspace
    attr_reader :name, :spec, :path, :ruby_bin, :log

    def initialize(spec, workdir:, gem_source:, workers:, log:)
      @name = spec.fetch('name')
      @workers = workers
      @spec = spec
      @path = File.join(workdir, 'projects', @name)
      @bundle_path = File.join(workdir, 'bundle', "#{@name}-ruby-#{spec.fetch('ruby')}")
      @gem_source = gem_source
      @log = log
      @ruby_bin = find_ruby(spec.fetch('ruby'))
      @originals = {}
    end

    def env(extra = {})
      base = ENV.to_h.reject { |key, _| key.start_with?('BUNDLE_', 'GEM_') || STRIPPED_ENV.include?(key) }
      base.merge('PATH' => "#{@ruby_bin}:#{ENV.fetch('PATH')}", 'BUNDLE_GEMFILE' => gemfile,
                 'BUNDLE_PATH' => @bundle_path).merge(project_env).merge(extra).compact
    end

    def project_env
      spec.fetch('env').transform_values { |value| value == '{workers}' ? @workers.to_s : value }
    end

    def gemfile
      File.join(@path, 'Gemfile.benchmark')
    end

    def run(*args, env: {}, chdir: @path)
      output, status = Open3.capture2e(self.env(env), *args, chdir: chdir, unsetenv_others: true)
      File.open(@log, 'a') { |file| file.puts("$ #{args.join(' ')}\n#{output}") }
      return output if status.success?

      raise SetupError, "#{name}: #{args.join(' ')} failed (#{status.exitstatus}):\n#{output[-4000..] || output}"
    end

    def git(*args)
      run('git', '-C', @path, *args)
    end

    def prepare(lockfile_replay:)
      missing = spec.fetch('requires').reject { |tool| executable?(tool) }
      raise SetupError, "#{name}: install or put on PATH: #{missing.join(', ')}" unless missing.empty?

      timings = {}
      timings[:checkout] = timed { checkout }
      timings[:gems] = timed { install_gems(lockfile_replay) }
      timings[:services] = timed { start_services }
      spec.fetch('setup').each_with_index do |step, index|
        next if step['creates'] && File.exist?(File.join(@path, step.fetch('creates')))

        timings[:"setup_#{index}"] = timed { run(*step.fetch('run')) }
      end
      remember
      verify_clean
      timings
    end

    def checkout
      validate_path
      clone
      ([spec.fetch('commit')] + spec.fetch('changes').map { |change| change.fetch('commit') }).each { fetch(_1) }
      verify_tag
      git('-c', 'advice.detachedHead=false', 'checkout', '--force', '--detach', spec.fetch('commit'))
      git('clean', '-ffdq')
      write_excludes
      write_tracer_configs
    end

    def clone
      return if File.directory?(File.join(@path, '.git'))

      FileUtils.mkdir_p(File.dirname(@path))
      run('git', 'clone', '--filter=blob:none', '--no-checkout', spec.fetch('repository'), @path,
          chdir: File.dirname(@path))
    end

    def verify_tag
      tagged = git('rev-parse', "#{spec.fetch('tag')}^{commit}").strip
      return if tagged == spec.fetch('commit')

      raise SetupError, "#{name}: tag #{spec['tag']} is #{tagged}, not #{spec['commit']}"
    end

    def fetch(commit)
      git('cat-file', '-e', "#{commit}^{commit}")
    rescue SetupError
      git('fetch', '--filter=blob:none', 'origin', commit)
    end

    def validate_path
      hidden = @path.split('/').grep(/\A\.[^.]/)
      return if hidden.empty?

      raise SetupError, "workspace path #{@path} has hidden components (#{hidden.join(', ')}); " \
                        'RuboCop and other projects skip hidden directories in glob specs'
    end

    def write_excludes
      exclude = File.join(@path, '.git', 'info', 'exclude')
      outputs = TRACERS.values.flat_map { |tracer| tracer.fetch(:outputs).map { |dir| "/#{dir}/" } }
      entries = %w[/Gemfile.benchmark /Gemfile.benchmark.lock] +
        TRACERS.values.map { |tracer| "/#{tracer.fetch(:config)}" } + outputs
      current = File.exist?(exclude) ? File.read(exclude) : ''
      missing = entries.reject { |entry| current.lines.map(&:strip).include?(entry) }
      File.write(exclude, current + missing.map { "#{_1}\n" }.join) unless missing.empty?
    end

    def write_tracer_configs
      body = spec.fetch('tracer_config').map { "  #{_1}\n" }.join
      TRACERS.each_value do |tracer|
        File.write(File.join(@path, tracer.fetch(:config)),
                   "# Written by benchmark/oss/run.rb\n#{tracer.fetch(:constant)}.configure do\n#{body}end\n")
      end
    end

    def install_gems(lockfile_replay)
      if spec['lockfile']
        lock = File.join(@path, 'Gemfile.lock')
        git('check-ignore', '-q', 'Gemfile.lock')
        FileUtils.cp(File.join(__dir__, spec.fetch('lockfile')), lock)
      end
      File.write(gemfile, <<~RUBY)
        eval_gemfile File.expand_path('Gemfile', __dir__)
        #{@gem_source}
        gem 'rspec-tracer', '= #{RSPEC_TRACER_VERSION}', require: false
      RUBY
      benchmark_lock = "#{gemfile}.lock"
      if lockfile_replay
        File.write(benchmark_lock, lockfile_replay)
      else
        FileUtils.cp(File.join(@path, 'Gemfile.lock'), benchmark_lock)
      end
      run('bundle', 'install', '--jobs', '8', env: { 'BUNDLE_FROZEN' => 'false' })
      run('bundle', 'check')
      verify_conservative_lock(benchmark_lock) unless lockfile_replay
    end

    def verify_conservative_lock(benchmark_lock)
      pattern = /^    (\S+) \((\S+)\)$/
      project = File.read(File.join(@path, 'Gemfile.lock')).scan(pattern)
      changed = project - File.read(benchmark_lock).scan(pattern)
      return if changed.empty?

      raise SetupError, "#{name}: adding the tracers changed locked gems: #{changed.first(10).inspect}"
    end

    def start_services
      services = spec.fetch('services')
      return if services.empty?

      run('docker', 'compose', '-f', File.join(__dir__, 'services.yml'), '-p', 'testsift-oss', 'up', '-d', '--wait',
          *services, chdir: __dir__)
    end

    def service_images
      spec.fetch('services').to_h do |service|
        container = run('docker', 'compose', '-f', File.join(__dir__, 'services.yml'), '-p', 'testsift-oss',
                        'ps', '-q', service, chdir: __dir__).strip
        [service, run('docker', 'inspect', '--format', '{{.Config.Image}} {{.Image}}', container, chdir: __dir__).strip]
      end
    end

    def remember
      TRACERS.each_value { |tracer| snapshot(tracer.fetch(:config)) }
      snapshot(spec.dig('fault', 'path')) if spec['fault']
    end

    def snapshot(relative)
      return if @originals.key?(relative)

      full = File.join(@path, relative)
      @originals[relative] = File.exist?(full) ? [File.binread(full), File.mtime(full)] : nil
    end

    # Restores every path a mutation touched, with its original mtime, and
    # deletes all tracer output, so each sample starts from the same bytes.
    def reset
      @originals.each do |relative, original|
        full = File.join(@path, relative)
        if original
          FileUtils.mkdir_p(File.dirname(full))
          File.binwrite(full, original[0])
          File.utime(original[1], original[1], full)
        else
          FileUtils.rm_rf(full)
        end
      end
      clear_outputs
      spec.fetch('reset').each { |step| run(*step) }
      verify_clean
    end

    def clear_outputs
      TRACERS.each_value { |tracer| tracer.fetch(:outputs).each { |dir| FileUtils.rm_rf(File.join(@path, dir)) } }
    end

    def verify_clean
      status = git('status', '--porcelain', '--untracked-files=all')
      raise SetupError, "#{name}: workspace differs from the pin:\n#{status}" unless status.empty?
    end

    def apply_patch(patch, paths)
      paths.each { |relative| snapshot(relative) }
      run('git', 'apply', '--whitespace=nowarn', patch)
    end

    def patch_for(change)
      commit = change.fetch('commit')
      [git('diff', '--binary', "#{commit}^", commit),
       git('diff', '--name-only', '--no-renames', "#{commit}^", commit).lines.map(&:strip)]
    end

    def replace(relative, from, to)
      full = File.join(@path, relative)
      text = File.binread(full)
      unless text.scan(from).size == 1
        raise SetupError,
              "#{name}: #{relative} does not contain #{from.inspect} exactly once"
      end

      File.binwrite(full, text.sub(from, to))
    end

    def append(relative, text)
      File.open(File.join(@path, relative), 'a') { |file| file.write(text) }
    end

    def ruby_description
      run('ruby', '-v').strip
    end

    def tool_versions
      spec.fetch('versions').to_h { |probe| [probe.join(' '), run(*probe).lines.first.to_s.strip] }
    end

    private

    def timed
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    end

    def executable?(tool)
      env.fetch('PATH').split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, tool)) }
    end

    def find_ruby(version)
      RUBY_ROOTS.each do |root|
        bin = File.join(File.expand_path(format(root, version)), 'bin')
        next unless File.executable?(File.join(bin, 'ruby'))

        actual, = Open3.capture2(File.join(bin, 'ruby'), '-e', 'print RUBY_VERSION')
        return bin if actual == version
      end
      raise SetupError, "#{name}: Ruby #{version} not found under #{RUBY_ROOTS.join(', ')}"
    end
  end
end
