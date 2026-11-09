# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'optparse'
require 'time'
require 'yaml'

require_relative '../evidence/host'
require_relative 'workspace'
require_relative 'project_run'
require_relative 'report'

module OSSBenchmark
  Host = PerformanceEvidence::Host
  ROOT = File.expand_path('../..', __dir__)
  BOOT = File.join(__dir__, 'boot.rb')
  MANIFEST = File.join(__dir__, 'corpus.yml')
  CONTROL_CASES = %w[plain coverage_control].freeze
  TRACER_CASES = %w[full warm changed invalidated fault].freeze
  CASES = (CONTROL_CASES + TRACER_CASES).freeze
  COVERAGE_MODES = 'lines'
  INVALIDATION = "# invalidated by benchmark/oss/run.rb\n"
  DRIVERS = %w[run.rb project_run.rb validation.rb workspace.rb report.rb boot.rb corpus.yml services.yml
               ../evidence/host.rb].freeze

  class EvidenceError < StandardError; end

  class Runner
    attr_reader :options, :testsift

    def initialize(options)
      @options = options
      @output = File.expand_path(options.fetch(:output), ROOT)
      raise ArgumentError, "output already exists: #{@output}" if File.exist?(@output)

      @manifest = YAML.safe_load_file(MANIFEST)
      @rows = []
      @failures = []
      @projects = {}
    end

    def run
      FileUtils.mkdir_p(@output)
      @gem_source = prepare_testsift
      metadata = base_metadata
      @options.fetch(:projects).each do |name|
        run_project(name, metadata)
      rescue SetupError, EvidenceError => e
        @failures << { project: name, error: e.message }
        warn "#{name}: #{e.message}"
      end
      finish(metadata)
    end

    def runner(spec)
      name = @options[:runner] || spec.fetch('default_runner')
      spec.fetch('runners').fetch(name).merge('name' => name)
    end

    def workers(spec)
      @options[:workers] || runner(spec).fetch('workers')
    end

    def expected_processes(spec)
      workers(spec) + runner(spec).fetch('extra_processes')
    end

    private

    def write_json(name, data)
      File.write(File.join(@output, name), JSON.pretty_generate(data))
    end

    def host_command(*args)
      output, status = Open3.capture2e(*args, chdir: ROOT)
      raise SetupError, "#{args.join(' ')} failed:\n#{output}" unless status.success?

      output
    end

    def prepare_testsift
      if @options[:testsift_version]
        @testsift = { source: 'rubygems', version: @options[:testsift_version] }
        return "gem 'testsift', '= #{@options[:testsift_version]}', require: false"
      end

      revision = host_command('git', 'rev-parse', "#{@options[:revision] || 'HEAD'}^{commit}").strip
      directory = File.join(@output, 'testsift')
      archive = File.join(@output, 'testsift.tar')
      FileUtils.mkdir_p(directory)
      host_command('git', 'archive', '--format=tar', "--output=#{archive}", revision)
      host_command('tar', '-xf', archive, '-C', directory)
      version = File.read(File.join(directory, 'lib/testsift/version.rb'))[/VERSION = '([^']+)'/, 1]
      @testsift = { source: 'revision', revision: revision, version: version, path: directory }
      "gem 'testsift', path: #{directory.inspect}, require: false"
    end

    def base_metadata
      { recorded_at: Time.now.utc.iso8601, driver_revision: host_command('git', 'rev-parse', 'HEAD').strip,
        driver_dirty: !host_command('git', 'status', '--porcelain', '--', 'benchmark/oss').empty?,
        driver_sha256: DRIVERS.to_h { |file| [file, Digest::SHA256.file(File.join(__dir__, file)).hexdigest] },
        command: [RbConfig.ruby, $PROGRAM_NAME, *@options.fetch(:arguments)], options: @options.except(:arguments),
        testsift: @testsift, rspec_tracer: { source: 'rubygems', version: RSPEC_TRACER_VERSION },
        coverage: { tracer_cases: 'tracer owns Coverage.start (lines mode by default); project SimpleCov off',
                    coverage_control: "benchmark preload starts Coverage(#{COVERAGE_MODES}) without a tracer",
                    plain: 'no Coverage' },
        docker: docker_version, **Host.description, projects: {} }.tap { |data| write_json('metadata.json', data) }
    end

    def docker_version
      output, status = Open3.capture2e('docker', 'version', '--format', '{{.Server.Version}}')
      status.success? ? output.strip : 'unavailable'
    end

    def run_project(name, metadata)
      spec = @manifest.fetch('projects').fetch(name).merge('name' => name)
      directory = File.join(@output, 'projects', name)
      FileUtils.mkdir_p(directory)
      workspace = Workspace.new(spec, workdir: @options.fetch(:workdir), gem_source: @gem_source,
                                      workers: workers(spec), log: File.join(directory, 'setup.log'))
      warn "#{name}: preparing #{workspace.path}"
      setup = workspace.prepare(lockfile_replay: replay_lockfile(name))
      project = ProjectRun.new(self, workspace, directory)
      @projects[name] = project.state
      metadata[:projects][name] = project_metadata(spec, workspace, setup)
      write_json('metadata.json', metadata)
      project.execute { |row| record(row) }
    end

    def record(row)
      @rows << row
      File.open(File.join(@output, 'runs.jsonl'), 'a') { |file| file.puts(JSON.generate(row)) }
    end

    def finish(metadata)
      write_json('metadata.json', metadata)
      summary = Report.summarize(@rows, @projects, @failures)
      write_json('summary.json', summary)
      File.write(File.join(@output, 'report.md'), Report.markdown(summary, metadata))
      warn "Evidence saved to #{@output}"
      summary.fetch(:valid)
    end

    def replay_lockfile(name)
      return nil unless @options[:lockfiles]

      JSON.parse(File.read(@options[:lockfiles])).dig('projects', name, 'benchmark_lockfile', 'content') ||
        raise(SetupError, "#{@options[:lockfiles]} has no lockfile for #{name}")
    end

    def project_metadata(spec, workspace, setup)
      lock = File.read("#{workspace.gemfile}.lock")
      { repository: spec.fetch('repository'), tag: spec.fetch('tag'), commit: spec.fetch('commit'),
        license: spec.fetch('license'), workspace: workspace.path, ruby: workspace.ruby_description,
        bundler: workspace.run('bundle', '-v').strip, env: workspace.project_env, runner: runner(spec),
        suite: @options.fetch(:suite), suite_paths: spec.fetch('suites').fetch(@options.fetch(:suite)),
        workers: workers(spec), expected_processes: expected_processes(spec),
        tracer_config: spec.fetch('tracer_config'), changes: spec.fetch('changes'), fault: spec['fault'],
        services: workspace.service_images, tool_versions: workspace.tool_versions, setup_seconds: setup,
        benchmark_lockfile: { sha256: Digest::SHA256.hexdigest(lock), content: lock } }
    end
  end

  def self.main(arguments = ARGV)
    options = { projects: nil, suite: 'full', cases: CASES.dup, tracers: ['testsift'], repetitions: 5,
                seed: 30_031, workdir: '/var/tmp/testsift-oss',
                output: "tmp/oss/#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}", arguments: arguments.dup }
    parser(options).parse!(arguments.dup)
    validate(options)
    exit(Runner.new(options).run ? 0 : 1)
  end

  def self.parser(options)
    OptionParser.new do |flags|
      flags.banner = 'Usage: task benchmark:oss -- [options]'
      selection_flags(flags, options)
      source_flags(flags, options)
      flags.on('--repetitions N', Integer) { |value| options[:repetitions] = value }
      flags.on('--seed N', Integer) { |value| options[:seed] = value }
      flags.on('--workdir PATH') { |value| options[:workdir] = File.expand_path(value) }
      flags.on('--output PATH') { |value| options[:output] = value }
    end
  end

  def self.selection_flags(flags, options)
    flags.on('--projects LIST', Array) { |value| options[:projects] = value }
    flags.on('--suite NAME', 'full or a fixed subset named in corpus.yml') { |value| options[:suite] = value }
    flags.on('--cases LIST', Array, CASES.join(',')) { |value| options[:cases] = value }
    flags.on('--tracers LIST', Array, TRACERS.keys.join(',')) { |value| options[:tracers] = value }
    flags.on('--runner NAME', 'runner named in corpus.yml') { |value| options[:runner] = value }
    flags.on('--workers N', Integer) { |value| options[:workers] = value }
  end

  def self.source_flags(flags, options)
    flags.on('--revision REV', 'TestSift revision to measure') { |value| options[:revision] = value }
    flags.on('--testsift-version VERSION', 'measure a released gem') { |value| options[:testsift_version] = value }
    flags.on('--lockfiles METADATA', 'replay benchmark lockfiles') do |value|
      options[:lockfiles] = File.expand_path(value)
    end
  end

  def self.validate(options)
    projects = YAML.safe_load_file(MANIFEST).fetch('projects')
    options[:projects] ||= projects.keys
    validate_names(options, projects)
    raise ArgumentError, 'repetitions must be positive' unless options[:repetitions].positive?
    raise ArgumentError, 'pass --revision or --testsift-version, not both' if options[:testsift_version] &&
      options[:revision]

    options[:projects].each { |name| validate_project(name, projects.fetch(name), options) }
  end

  def self.validate_names(options, projects)
    unknown = { project: options[:projects] - projects.keys, case: options[:cases] - CASES,
                tracer: options[:tracers] - TRACERS.keys }.reject { |_, values| values.empty? }
    return if unknown.empty?

    raise ArgumentError, "unknown #{unknown.map { |kind, values| "#{kind}: #{values.join(', ')}" }.join('; ')}"
  end

  def self.validate_project(name, project, options)
    raise ArgumentError, "#{name} has no suite #{options[:suite]}" unless project.fetch('suites').key?(options[:suite])

    runner = project.fetch('runners').fetch(options[:runner] || project.fetch('default_runner')) do
      raise ArgumentError, "#{name} has no runner #{options[:runner]}"
    end
    return unless options[:workers] && runner.fetch('workers') == 1

    raise ArgumentError, "#{name}'s #{options[:runner] || project['default_runner']} runner is serial; drop --workers"
  end
end

OSSBenchmark.main if $PROGRAM_NAME == __FILE__
