# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'optparse'
require 'rbconfig'
require 'time'

require_relative 'host'

module PerformanceEvidence
  ROOT = File.expand_path('../..', __dir__)
  BOOT = File.join(__dir__, 'boot.rb')
  FIXTURES = { 'ruby' => 'benchmark/fixtures/ruby_app', 'rails' => 'spec/fixtures/rails_app' }.freeze
  OUTPUTS = %w[testsift_cache testsift_report testsift_coverage coverage testsift.lock
               evidence_branch_report].freeze
  CASES = %w[plain coverage_control full warm changed_source changed_input invalidated fault].freeze

  class Runner
    def initialize(options)
      @options = options
      @output = File.expand_path(options.fetch(:output), ROOT)
      raise ArgumentError, "output already exists: #{@output}" if File.exist?(@output)

      @rows = []
      @seeds = {}
      @originals = {}
      @oracles = {}
    end

    def run
      prepare
      prime
      rounds
      File.write(File.join(@output, 'summary.json'), JSON.pretty_generate(summary))
      warn "Evidence saved to #{@output}"
    end

    private

    def command(*args, chdir: ROOT, env: {})
      output, status = Open3.capture2e(env, *args, chdir: chdir)
      raise "#{args.inspect} failed (#{status.exitstatus}):\n#{output}" unless status.success?

      output
    end

    def prepare
      FileUtils.mkdir_p(@output)
      @revision = command('git', 'rev-parse', @options.fetch(:revision)).strip
      archive = File.join(@output, 'source.tar')
      command('git', 'archive', '--format=tar', "--output=#{archive}", @revision)
      @work = File.join(@output, 'work')
      FileUtils.mkdir_p(@work)
      command('tar', '-xf', archive, '-C', @work)
      @options.fetch(:fixtures).each { |fixture| prepare_fixture(fixture) }
      File.write(File.join(@output, 'metadata.json'), JSON.pretty_generate(metadata))
    end

    def prepare_fixture(fixture)
      relative = FIXTURES.fetch(fixture)
      destination = File.join(@work, relative)
      copy_lockfile(fixture, destination)
      if fixture == 'ruby'
        helper = File.join(destination, 'spec/spec_helper.rb')
        replacement = "if ENV['EVIDENCE_TRACER'] == '1'\n  require 'testsift'\n  TestSift.start\nend"
        File.write(helper, File.read(helper).sub("require 'testsift'\n\nTestSift.start", replacement))
      else
        env = { 'RAILS_ENV' => 'test', 'BUNDLE_GEMFILE' => File.join(destination, 'Gemfile') }
        command('bundle', 'exec', 'rails', 'db:test:prepare', chdir: destination, env: env)
      end
    end

    def copy_lockfile(fixture, destination)
      metadata_path = @options[:lockfiles]
      if metadata_path
        data = JSON.parse(File.read(metadata_path)).fetch('lockfiles').fetch(fixture)
        File.write(File.join(destination, 'Gemfile.lock'), data.fetch('content'))
        command('bundle', 'install', chdir: destination,
                                     env: { 'BUNDLE_GEMFILE' => File.join(destination, 'Gemfile') })
      else
        FileUtils.cp(File.join(ROOT, FIXTURES.fetch(fixture), 'Gemfile.lock'), destination)
      end
    end

    def metadata
      {
        baseline_revision: @revision, driver_revision: command('git', 'rev-parse', 'HEAD').strip,
        driver_sha256: [__FILE__, BOOT].to_h { |path| [File.basename(path), Digest::SHA256.file(path).hexdigest] },
        recorded_at: Time.now.utc.iso8601, ruby: RUBY_DESCRIPTION,
        **Host.description,
        options: @options, bundle_path: ENV.fetch('BUNDLE_PATH', nil),
        lockfiles: @options.fetch(:fixtures).to_h do |fixture|
          path = File.join(@work, FIXTURES.fetch(fixture), 'Gemfile.lock')
          [fixture, { sha256: Digest::SHA256.file(path).hexdigest, content: File.read(path) }]
        end
      }
    end

    def cwd(fixture)
      File.join(@work, FIXTURES.fetch(fixture))
    end

    def paths(fixture)
      if fixture == 'ruby'
        { source: 'app/discount.rb', input: 'spec/discount_spec.rb', invalidator: '.testsift' }
      else
        { source: 'app/services/feature_flags.rb', input: 'config/features.json', invalidator: '.testsift' }
      end
    end

    def remember(fixture)
      paths(fixture).each_value do |relative|
        path = File.join(cwd(fixture), relative)
        @originals[path] = File.binread(path)
      end
    end

    def restore_sources
      @originals.each { |path, content| File.binwrite(path, content) }
    end

    def clear(fixture)
      OUTPUTS.each { |relative| FileUtils.rm_rf(File.join(cwd(fixture), relative)) }
    end

    def identity(path)
      files = Dir.glob(File.join(path, '**/*')).select { |entry| File.file?(entry) }.sort
      Digest::SHA256.hexdigest(files.map do |entry|
        "#{entry.delete_prefix(path)}/#{Digest::SHA256.file(entry).hexdigest}"
      end.join("\n"))
    end

    def prime
      @options.fetch(:fixtures).each do |fixture|
        remember(fixture)
        @options.fetch(:modes).each do |mode|
          clear(fixture)
          row = invoke(fixture, mode, 'full', round: 'prime', profile: false, variant: 'stock')
          raise "baseline failed: #{row}" unless row.fetch(:exit_code).zero?
          raise 'fixture did not execute examples' if row.fetch(:selected).zero?

          seed = File.join(@output, 'seeds', "#{fixture}-#{mode}")
          FileUtils.mkdir_p(seed)
          OUTPUTS.each do |relative|
            path = File.join(cwd(fixture), relative)
            FileUtils.cp_r(path, seed) if File.exist?(path)
          end
          @seeds[[fixture, mode]] = { path: seed, identity: identity(seed), total: row.fetch(:selected) }
          prime_oracle(fixture, mode)
        end
      end
    end

    def prime_oracle(fixture, mode)
      mutate(fixture, 'fault')
      oracle = invoke(fixture, mode, 'plain', round: 'oracle', profile: false, variant: 'stock')
      raise 'fault failed to produce a failing oracle' if oracle.fetch(:failures).empty?

      @oracles[[fixture, mode]] = oracle.fetch(:failures)
      restore_sources
    end

    def mutate(fixture, scenario)
      kind = { 'changed_source' => :source, 'changed_input' => :input, 'invalidated' => :invalidator,
               'fault' => :source }[scenario]
      return unless kind

      path = File.join(cwd(fixture), paths(fixture).fetch(kind))
      text = @originals.fetch(path)
      changed = if scenario == 'fault'
                  fixture == 'ruby' ? text.sub('100.0', '50.0') : text.sub('== true', '== false')
                elsif scenario == 'changed_source'
                  fixture == 'ruby' ? text.sub('100.0', '100.00') : text.sub('== true', '== (true)')
                else
                  "#{text}\n"
                end
      raise 'mutation did not change bytes' if changed == text

      File.binwrite(path, changed)
    end

    def prepare_case(fixture, mode, scenario)
      restore_sources
      clear(fixture)
      seed = @seeds.fetch([fixture, mode])
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if %w[warm changed_source changed_input invalidated fault].include?(scenario)
        Dir.children(seed.fetch(:path)).each { |name| FileUtils.cp_r(File.join(seed.fetch(:path), name), cwd(fixture)) }
      end
      restored = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      mutate(fixture, scenario)
      restored
    end

    def rounds
      cells = @options.fetch(:fixtures).product(
        @options.fetch(:modes), @options.fetch(:cases), @options.fetch(:variants)
      )
      cells.reject! { |fixture, _, scenario, _| fixture == 'rails' && scenario == 'parallel_full' }
      random = Random.new(@options.fetch(:seed))
      total = @options.fetch(:repetitions) + @options.fetch(:profiles)
      total.times do |round|
        profile = round >= @options.fetch(:repetitions)
        cells.shuffle(random: random).each do |fixture, mode, scenario, variant|
          run_case(fixture, mode, scenario, round: round, profile: profile, variant: variant)
        end
      end
    ensure
      restore_sources
    end

    def run_case(fixture, mode, scenario, iteration)
      restore = prepare_case(fixture, mode, scenario)
      row = invoke(fixture, mode, scenario, iteration)
      seed = @seeds.fetch([fixture, mode])
      row.merge!(baseline_cache_identity: seed.fetch(:identity), total: seed.fetch(:total),
                 selected_ratio: row.fetch(:selected).fdiv(seed.fetch(:total)), external_seed_restore_seconds: restore)
      row[:omitted_failing_tests] = scenario == 'fault' ? @oracles.fetch([fixture, mode]) - row.fetch(:ids) : []
      validate(row)
      @rows << row
      File.open(File.join(@output, 'runs.jsonl'), 'a') { |file| file.puts(JSON.generate(row)) }
      warn "#{@rows.size}: #{fixture}/#{mode}/#{scenario}/#{iteration.fetch(:variant)} " \
           "profile=#{iteration.fetch(:profile)} " \
           "#{row.fetch(:wall_seconds).round(3)}s #{row.fetch(:selected)}/#{seed.fetch(:total)}"
    end

    def validate(row)
      scenario = row.fetch(:scenario)
      expected_exit = scenario == 'fault' ? 1 : 0
      raise "unexpected exit: #{row}" unless row.fetch(:exit_code) == expected_exit

      validate_discovery(row)
      validate_fault_oracle(row) if scenario == 'fault'
      validate_full_run(row) if %w[full invalidated parallel_full].include?(scenario)
    end

    def validate_discovery(row)
      discovered = row.fetch(:telemetry).sum { |data| data.fetch('discovery') }
      raise "discovery count mismatch: #{discovered} != #{row.fetch(:total)}" unless discovered == row.fetch(:total)
    end

    def validate_full_run(row)
      validate_app_execution(row) if row.fetch(:profile)
      validate_worker_merge(row) if row.fetch(:scenario) == 'parallel_full'
      raise "incomplete full run: #{row}" unless row.fetch(:selected) == row.fetch(:total)
    end

    def validate_worker_merge(row)
      return if row.fetch(:cache_examples) == row.fetch(:total)

      raise "incomplete merged cache: #{row}"
    end

    def validate_fault_oracle(row)
      raise "omitted failing tests: #{row}" unless row.fetch(:omitted_failing_tests).empty?
      return if row.fetch(:failures).sort == @oracles.fetch(row.values_at(:fixture, :mode)).sort

      raise "failure oracle mismatch: #{row}"
    end

    def validate_app_execution(row)
      executed = row.fetch(:telemetry).sum { |data| data.fetch('app_executed_lines') }
      raise "fixture did not execute app code: #{row}" if executed.zero?
    end

    def invoke(fixture, mode, scenario, iteration)
      token = "#{fixture}-#{mode}-#{scenario}-#{iteration.values_at(:variant, :round, :profile).join('-')}"
      directory = File.join(@output, 'runs', token)
      FileUtils.mkdir_p(directory)
      env = environment(fixture, mode, scenario, directory, iteration)
      args = invocation(scenario, directory)
      time = File.join(directory, 'time.txt')
      full_command = Host.timed(args, time)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      output, status = Open3.capture2e(env, *full_command, chdir: cwd(fixture))
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      File.write(File.join(directory, 'output.log'), output)
      context = { fixture: fixture, mode: mode, scenario: scenario, command: full_command, env: env,
                  wall_seconds: elapsed, exit_code: status.exitstatus }.merge(iteration)
      measurements(directory, fixture).merge(context)
    end

    def environment(fixture, mode, scenario, directory, iteration)
      tracer = !%w[plain coverage_control].include?(scenario)
      { 'EVIDENCE_MODE' => scenario == 'plain' ? 'plain' : mode, 'EVIDENCE_TRACER' => tracer ? '1' : '0',
        'EVIDENCE_PROFILE' => iteration.fetch(:profile) ? '1' : '0',
        'EVIDENCE_TELEMETRY' => File.join(directory, 'telemetry'),
        'TESTSIFT' => tracer ? '1' : '0', 'TESTSIFT_FIXTURE_NO_SIMPLECOV' => '1',
        'RAILS_ENV' => 'test', 'COVERAGE' => 'false', 'TESTSIFT_DISABLE' => nil,
        'BUNDLE_GEMFILE' => File.join(cwd(fixture), 'Gemfile'), 'EVIDENCE_VARIANT' => iteration.fetch(:variant) }
    end

    def invocation(scenario, directory)
      if scenario == 'parallel_full'
        test_options = "--options /dev/null --require #{BOOT} --require spec_helper " \
                       "--format json --out #{directory}/rspec$TEST_ENV_NUMBER.json"
        ['bundle', 'exec', 'parallel_rspec', '-n', '2', '--test-options',
         test_options, 'spec']
      else
        ['bundle', 'exec', 'ruby', '-r', BOOT, '-S', 'rspec', '--format', 'json',
         '--out', File.join(directory, 'rspec.json')]
      end
    end

    def measurements(directory, fixture)
      payloads = read_payloads(directory, 'rspec*.json')
      examples = payloads.flat_map { |payload| payload.fetch('examples') }
      telemetry = read_payloads(directory, 'telemetry.*.json')
      raise "missing telemetry/results: #{directory}" if telemetry.empty? || payloads.empty?

      Host.resources(File.join(directory, 'time.txt')).merge(
        allocations: telemetry.sum { |payload| payload.fetch('allocations') }, telemetry: telemetry,
        cache_bytes: cache_size(fixture), cache_examples: cache_examples(fixture), selected: examples.size,
        ids: examples.map { |example| example.fetch('id') },
        failures: failed_ids(examples),
        artifact_directory: directory
      )
    end

    def read_payloads(directory, pattern)
      Dir.glob(File.join(directory, pattern)).map { |path| JSON.parse(File.read(path)) }
    end

    def cache_size(fixture)
      paths = Dir.glob(File.join(cwd(fixture), 'testsift_cache/**/*'))
      paths.select { |path| File.file?(path) }.sum { |path| File.size(path) }
    end

    def cache_examples(fixture)
      root = File.join(cwd(fixture), 'testsift_cache')
      manifest = File.join(root, 'last_run.json')
      return 0 unless File.file?(manifest)

      run_id = JSON.parse(File.read(manifest)).fetch('run_id')
      JSON.parse(File.read(File.join(root, run_id, 'all_examples.json'))).size
    end

    def failed_ids(examples)
      failed = examples.select { |example| example.fetch('status') == 'failed' }
      failed.map { |example| example.fetch('id') }
    end

    def percentile(values, fraction)
      sorted = values.sort
      sorted.fetch((fraction * sorted.length).ceil - 1)
    end

    def summary
      @rows.group_by { |row| row.values_at(:fixture, :mode, :scenario, :profile, :variant) }.map do |key, rows|
        { fixture: key[0], mode: key[1], scenario: key[2], profile: key[3], variant: key[4], repetitions: rows.size,
          p50_seconds: percentile(rows.map { |row| row.fetch(:wall_seconds) }, 0.5),
          p95_seconds: percentile(rows.map { |row| row.fetch(:wall_seconds) }, 0.95),
          median_peak_rss_kib: percentile(rows.map { |row| row.fetch(:peak_rss_kib) }, 0.5),
          median_allocations: percentile(rows.map { |row| row.fetch(:allocations) }, 0.5),
          cache_bytes: range(rows, :cache_bytes), selected_ratio: range(rows, :selected_ratio),
          omitted_failing_tests: rows.sum { |row| row.fetch(:omitted_failing_tests).size } }
      end
    end

    def range(rows, field)
      rows.map { |row| row.fetch(field) }.minmax
    end
  end

  def self.main
    options = { repetitions: 20, profiles: 3, seed: 30_031, fixtures: FIXTURES.keys,
                modes: %w[dependency lines branches], revision: 'f13851f7b3393aaafa7c7df088c1605747f07ce5',
                output: "tmp/evidence-#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}",
                cases: CASES + ['parallel_full'], variants: ['stock'] }
    parse_options(options)
    validate_options(options)
    Runner.new(options).run
  end

  def self.parse_options(options)
    OptionParser.new do |parser|
      parser.on('--repetitions N', Integer) { |value| options[:repetitions] = value }
      parser.on('--profiles N', Integer) { |value| options[:profiles] = value }
      parser.on('--seed N', Integer) { |value| options[:seed] = value }
      parser.on('--fixtures LIST', Array) { |value| options[:fixtures] = value }
      parser.on('--modes LIST', Array) { |value| options[:modes] = value }
      parser.on('--cases LIST', Array) { |value| options[:cases] = value }
      parser.on('--variant NAME') { |value| options[:variants] = [value] }
      parser.on('--variants LIST', Array) { |value| options[:variants] = value }
      parser.on('--revision SHA') { |value| options[:revision] = value }
      parser.on('--output PATH') { |value| options[:output] = value }
      parser.on('--lockfiles METADATA') { |value| options[:lockfiles] = File.expand_path(value) }
    end.parse!
  end

  def self.validate_options(options)
    raise ArgumentError, 'invalid repetition counts' unless options[:repetitions].positive? && options[:profiles] >= 0
    raise ArgumentError, 'unknown fixture' unless (options[:fixtures] - FIXTURES.keys).empty?
    raise ArgumentError, 'unknown mode' unless (options[:modes] - %w[dependency lines branches]).empty?
    raise ArgumentError, 'unknown case' unless (options[:cases] - CASES - ['parallel_full']).empty?
    raise ArgumentError, 'unknown variant' unless (options[:variants] - %w[stock share_snapshot]).empty?
  end
end

PerformanceEvidence.main if $PROGRAM_NAME == __FILE__
