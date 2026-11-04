# frozen_string_literal: true

require_relative 'run'
require_relative 'corpus'

module PerformanceEvidence
  class CurrentRunner < Runner
    BOOT = File.join(__dir__, 'current_boot.rb')

    private

    def prepare
      super
      @malloc_probe = File.join(@output, 'malloc_probe.so')
      command('cc', '-shared', '-fPIC', '-O2', '-o', @malloc_probe, File.join(__dir__, 'malloc_probe.c'))
    end

    def prepare_fixture(fixture)
      return super unless @options[:corpus]

      raise ArgumentError, 'corpus requires the ruby fixture alone' unless @options.fetch(:fixtures) == ['ruby']

      Corpus.new(@options.fetch(:corpus)).write(cwd(fixture))
      gemfile = File.join(cwd(fixture), 'Gemfile')
      File.open(gemfile, 'a') do |file|
        file.puts "gem 'msgpack', '= 1.8.7', require: false"
        file.puts "gem 'sqlite3', '= 2.10.2', require: false"
      end
      super
      return if @options[:lockfiles]

      command('bundle', 'install', chdir: cwd(fixture), env: { 'BUNDLE_GEMFILE' => gemfile })
    end

    def metadata
      files = %w[current.rb current_boot.rb corpus.rb cache_probe.rb run.rb boot.rb malloc_probe.c]
      super.merge(engine_revision: @revision,
                  driver_sha256: files.to_h { |name| [name, Digest::SHA256.file(File.join(__dir__, name)).hexdigest] },
                  root_lockfile: File.read(File.join(ROOT, 'Gemfile.lock')),
                  remote: 'unmeasured; no authorized remote backend configured',
                  coverage_owner: 'benchmark bootstrap; fixture SimpleCov disabled',
                  corpus_identity: @options[:corpus] ? identity(cwd('ruby')) : nil,
                  command: [RbConfig.ruby, $PROGRAM_NAME, *@options.fetch(:command_arguments)],
                  rubyopt: ENV.fetch('RUBYOPT', nil), compiler: command('cc', '--version').lines.first.strip)
    end

    def paths(fixture)
      return super unless @options[:corpus]

      { source: 'app/work_0.rb', input: 'inputs/input_0.json', invalidator: '.rspec-tracer' }
    end

    def mutate(fixture, scenario)
      return super unless @options[:corpus] || scenario == 'input_fault'

      kind = { 'changed_source' => :source, 'changed_input' => :input, 'invalidated' => :invalidator,
               'fault' => :source, 'input_fault' => :input }[scenario]
      return unless kind

      path = File.join(cwd(fixture), paths(fixture).fetch(kind))
      original = @originals.fetch(path)
      changed = case scenario
                when 'fault'
                  original.sub('x >= 0', 'x < 0')
                when 'changed_source'
                  original.sub('x >= 0', 'x >= (0)')
                when 'input_fault'
                  input_defect(fixture, original)
                else
                  "#{original}\n"
                end
      raise 'mutation did not change bytes' if changed == original

      File.binwrite(path, changed)
    end

    def input_defect(fixture, original)
      return original.sub('"value":1', '"value":2') if @options[:corpus]
      return original.sub('eq(80.0)', 'eq(81.0)') if fixture == 'ruby'

      data = JSON.parse(original)
      data['comments_enabled'] = !data.fetch('comments_enabled')
      "#{JSON.pretty_generate(data)}\n"
    end

    def prime_oracle(fixture, mode)
      %w[fault input_fault].each do |scenario|
        mutate(fixture, scenario)
        row = invoke(fixture, mode, 'plain', round: "oracle-#{scenario}", profile: false, variant: 'stock')
        raise 'defect did not fail independent full runner' if row.fetch(:failures).empty?

        @oracles[[fixture, mode, scenario]] = row.fetch(:failures)
        restore_sources
      end
    end

    def prepare_case(fixture, mode, scenario)
      super(fixture, mode, scenario == 'input_fault' ? 'warm' : scenario).tap do
        mutate(fixture, scenario) if scenario == 'input_fault'
      end
    end

    def environment(fixture, mode, scenario, directory, iteration)
      environment = super.merge('RSPEC_TRACER_STORAGE' => @options.fetch(:backend),
                                'RSPEC_TRACER_STORAGE_SERIALIZER' => @options.fetch(:serializer),
                                'PARALLEL_TEST_GROUPS' => @options.fetch(:workers).to_s,
                                'EVIDENCE_MALLOC_PROBE' => @malloc_probe)
      if scenario == 'unwrapped_plain'
        environment['EVIDENCE_TRACER'] = '0'
        environment['RSPEC_TRACER'] = '0'
      end
      environment
    end

    def invocation(scenario, directory)
      if scenario == 'unwrapped_plain'
        return ['bundle', 'exec', 'rspec', '--format', 'json', '--out', File.join(directory, 'rspec.json')]
      end

      args = super.map do |argument|
        argument.gsub(PerformanceEvidence::BOOT, BOOT)
      end
      args[args.index('-n') + 1] = @options.fetch(:workers).to_s if scenario == 'parallel_full'
      args
    end

    def cache_examples(fixture)
      root = File.join(cwd(fixture), 'rspec_tracer_cache')
      return super if @options.fetch(:serializer) == 'json' && @options.fetch(:backend) == 'json'
      return 0 unless File.directory?(root)

      inspect_cache(fixture, 'count').to_i
    end

    def inspect_cache(fixture, field)
      root = File.join(cwd(fixture), 'rspec_tracer_cache')
      env = { 'BUNDLE_GEMFILE' => File.join(cwd(fixture), 'Gemfile') }
      command('bundle', 'exec', 'ruby', '-I', File.join(@work, 'lib'), File.join(__dir__, 'cache_probe.rb'),
              root, @options.fetch(:backend), @options.fetch(:serializer), field, chdir: cwd(fixture), env: env)
    end

    def measurements(directory, fixture)
      if File.basename(directory).include?('-unwrapped_plain-')
        resource = File.readlines(File.join(directory, 'time.txt')).last.split.map(&:to_f)
        examples = read_payloads(directory, 'rspec.json').flat_map { |payload| payload.fetch('examples') }
        return { peak_rss_kib: resource[0], user_seconds: resource[1], system_seconds: resource[2],
                 selected: examples.size, ids: examples.map { |example| example.fetch('id') },
                 failures: failed_ids(examples), telemetry: [], allocations: nil, cache_examples: 0,
                 cache_bytes: 0, report_bytes: 0, artifact_directory: directory }
      end

      super.merge(report_bytes: %w[rspec_tracer_report rspec_tracer_coverage evidence_branch_report].sum do |relative|
        files = Dir.glob(File.join(cwd(fixture), relative, '**/*')).select { |path| File.file?(path) }
        files.sum { |path| File.size(path) }
      end)
    end

    def run_case(fixture, mode, scenario, iteration)
      @oracles[[fixture, mode]] = @oracles[[fixture, mode, scenario]] if %w[fault input_fault].include?(scenario)
      restore = prepare_case(fixture, mode, scenario)
      row = invoke(fixture, mode, scenario, iteration)
      seed = @seeds.fetch([fixture, mode])
      row.merge!(baseline_cache_identity: seed.fetch(:identity), total: seed.fetch(:total),
                 selected_ratio: row.fetch(:selected).fdiv(seed.fetch(:total)), external_seed_restore_seconds: restore)
      record_oracle(row)
      @rows << row
      File.open(File.join(@output, 'runs.jsonl'), 'a') { |file| file.puts(JSON.generate(row)) }
      validate(row)
      warn "#{@rows.size}: #{fixture}/#{mode}/#{scenario} profile=#{row.fetch(:profile)} " \
           "#{row.fetch(:wall_seconds).round(3)}s #{row.fetch(:selected)}/#{seed.fetch(:total)}"
    end

    def record_oracle(row)
      scenario = row.fetch(:scenario)
      row[:oracle_failure_ids] = @oracles.fetch(row.values_at(:fixture, :mode) + [scenario], [])
      row[:omitted_failing_tests] = row[:oracle_failure_ids] - row.fetch(:ids)
      row[:failure_status_mismatches] = (row[:oracle_failure_ids] - row.fetch(:failures)) |
        (row.fetch(:failures) - row[:oracle_failure_ids])
    end

    def validate(row)
      raise 'omitted failing tests' unless row.fetch(:omitted_failing_tests).empty?
      raise 'oracle mismatch' unless row.fetch(:failure_status_mismatches).empty?

      validate_backend(row)
      if row.fetch(:scenario) == 'parallel_full' && row.fetch(:telemetry).size != @options.fetch(:workers)
        raise 'incorrect worker count'
      end

      if @options[:corpus] && %w[full parallel_full invalidated].include?(row.fetch(:scenario))
        validate_corpus_cache(row)
      end
      return validate_special_execution(row) if %w[unwrapped_plain input_fault].include?(row.fetch(:scenario))

      super
    end

    def validate_backend(row)
      return if %w[plain coverage_control unwrapped_plain].include?(row.fetch(:scenario))

      expected = if @options.fetch(:backend) == 'sqlite'
                   'RSpecTracer::Storage::SqliteBackend'
                 else
                   'RSpecTracer::Storage::JsonBackend'
                 end
      row.fetch(:telemetry).each do |data|
        raise 'storage backend fell back' unless data.fetch('storage_class') == expected
        next unless @options.fetch(:backend) == 'json'

        raise 'serializer fell back' unless data.fetch('serializer') == @options.fetch(:serializer)
      end
    end

    def validate_special_execution(row)
      scenario = row.fetch(:scenario)
      if scenario == 'unwrapped_plain'
        raise 'incomplete unwrapped run' unless row.fetch(:selected) == row.fetch(:total) && row.fetch(:exit_code).zero?
      elsif scenario == 'input_fault'
        validate_discovery(row)
        raise 'input defect not reproduced' unless row.fetch(:exit_code) == 1

        validate_fault_oracle(row)
      end
    end

    def validate_corpus_cache(row)
      snapshot = JSON.parse(inspect_cache(row.fetch(:fixture), 'graph'))
      examples = snapshot.fetch('all_examples')
      dependency = snapshot.fetch('dependency')
      raise 'incomplete corpus cache' unless examples.size == @options.fetch(:corpus).fetch(:examples)

      validate_corpus_dependencies(examples, dependency)
    end

    def validate_corpus_dependencies(examples, dependency)
      dimensions = @options.fetch(:corpus)
      examples.each do |id, example|
        index = Integer(example.fetch('description').match(/example (\d+)\z/)[1])
        sources = Array.new(dimensions.fetch(:fanout)) do |offset|
          "/app/work_#{(index + offset) % dimensions.fetch(:files)}.rb"
        end
        expected = sources + ["/inputs/input_#{index % dimensions.fetch(:inputs)}.json"]
        raise "missing independently expected dependencies: #{id}" unless (expected - dependency.fetch(id)).empty?
      end
    end

    def summary
      super.map do |cell|
        rows = @rows.select do |row|
          row.values_at(:fixture, :mode, :scenario, :profile, :variant) ==
            cell.values_at(:fixture, :mode, :scenario, :profile, :variant)
        end
        cell.merge(report_bytes: range(rows, :report_bytes),
                   p95_peak_rss_kib: percentile(rows.map { |row| row.fetch(:peak_rss_kib) }, 0.95),
                   p95_allocations: percentile(rows.map { |row| row.fetch(:allocations) }, 0.95),
                   oracle_failure_observations: rows.sum { |row| row.fetch(:oracle_failure_ids).size },
                   failure_status_mismatches: rows.sum { |row| row.fetch(:failure_status_mismatches).size })
      end
    end
  end

  def self.current_main
    options = { repetitions: 20, profiles: 3, seed: 30_031, fixtures: FIXTURES.keys,
                modes: %w[dependency lines branches], revision: 'e225fbf',
                output: "tmp/current-#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}",
                cases: CASES + %w[input_fault parallel_full], variants: ['stock'],
                workers: 2, backend: 'json', serializer: 'json' }
    arguments = ARGV.dup
    parse_current_options(options)
    validate_current_options(options)
    options[:command_arguments] = arguments
    CurrentRunner.new(options).run
  end

  def self.parse_current_options(options)
    OptionParser.new do |flags|
      flags.on('--repetitions N', Integer) { |value| options[:repetitions] = value }
      flags.on('--profiles N', Integer) { |value| options[:profiles] = value }
      flags.on('--seed N', Integer) { |value| options[:seed] = value }
      flags.on('--fixtures LIST', Array) { |value| options[:fixtures] = value }
      flags.on('--modes LIST', Array) { |value| options[:modes] = value }
      flags.on('--cases LIST', Array) { |value| options[:cases] = value }
      flags.on('--revision SHA') { |value| options[:revision] = value }
      flags.on('--output PATH') { |value| options[:output] = value }
      flags.on('--lockfiles METADATA') { |value| options[:lockfiles] = File.expand_path(value) }
      corpus_options(flags, options)
    end.parse!
  end

  def self.corpus_options(flags, options)
    flags.on('--corpus NAME') { |value| options[:corpus] = Corpus::PRESETS.fetch(value) }
    flags.on('--corpus-file PATH') { |value| options[:corpus] = JSON.parse(File.read(value), symbolize_names: true) }
    flags.on('--workers N', Integer) { |value| options[:workers] = value }
    flags.on('--backend NAME') { |value| options[:backend] = value }
    flags.on('--serializer NAME') { |value| options[:serializer] = value }
  end

  def self.validate_current_options(options)
    validate_options(options.merge(cases: options.fetch(:cases) - %w[input_fault unwrapped_plain]))
    raise ArgumentError, 'empty experiment' if options.values_at(:fixtures, :modes, :cases).any?(&:empty?)
    raise ArgumentError, 'workers must be 1..4' unless (1..4).cover?(options.fetch(:workers))

    validate_storage_options(options)
  end

  def self.validate_storage_options(options)
    raise ArgumentError, 'unknown backend' unless %w[json sqlite].include?(options.fetch(:backend))
    raise ArgumentError, 'unknown serializer' unless %w[json msgpack].include?(options.fetch(:serializer))
    if options[:backend] == 'sqlite' && options[:serializer] != 'json'
      raise ArgumentError,
            'sqlite has no serializer option'
    end
    return unless options[:backend] == 'sqlite' && options[:cases].include?('parallel_full')

    raise ArgumentError,
          'parallel requires json backend'
  end
end

PerformanceEvidence.current_main if $PROGRAM_NAME == __FILE__
