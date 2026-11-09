# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open3'

require_relative '../evidence/host'
require_relative 'validation'

module OSSBenchmark
  # The measured cells of one project. Each sample restores the workspace,
  # restores the requested seed cache, applies its mutation, and times the
  # project's own runner from spawn through every worker's exit.
  class ProjectRun
    attr_reader :state

    def initialize(runner, workspace, directory)
      @runner = runner
      @options = runner.options
      @workspace = workspace
      @spec = workspace.spec
      @directory = directory
      @oracles = {}
      @seeds = {}
      @patches = {}
      @state = { oracles: @oracles, seeds: {} }
    end

    def execute(&record)
      @record = record
      preflight
      oracles
      @options.fetch(:tracers).each { |tracer| prime(tracer) } unless tracer_cases.empty?
      rounds
    ensure
      @workspace.reset
    end

    private

    def tracer_cases
      @options.fetch(:cases) & TRACER_CASES
    end

    def changes
      @spec.fetch('changes')
    end

    def preflight
      runs = Array.new(2) { |index| sample('plain', nil, nil, round: "preflight-#{index}") }
      runs.each do |row|
        raise EvidenceError, "plain baseline is not passing: #{row.fetch(:errors).join('; ')}" unless row[:valid]
        raise EvidenceError, "plain baseline fails: #{row.fetch(:failures).first(10)}" unless row[:failures].empty?
      end
      raise EvidenceError, 'plain baseline discovered no examples' if runs.first.fetch(:executed).zero?
      raise EvidenceError, 'plain baseline is not repeatable' unless runs.map { Validation.executed_ids(_1) }.uniq.one?

      @oracles['base'] = oracle(runs.first)
    end

    def oracles
      changes.each do |change|
        @oracles[change.fetch('name')] = oracle(valid_oracle(change.fetch('name')))
      end
      row = valid_oracle('fault')
      raise EvidenceError, 'fault did not fail the independent plain run' if row.fetch(:failures).empty?

      @oracles['fault'] = oracle(row)
    end

    def valid_oracle(variant)
      row = sample('plain', nil, variant, round: 'oracle')
      raise EvidenceError, "#{variant} oracle is incomplete: #{row.fetch(:errors).join('; ')}" unless row[:valid]

      row
    end

    def oracle(row)
      { ids: Validation.executed_ids(row), failures: row.fetch(:failures), total: row.fetch(:executed) }
    end

    def prime(tracer)
      row = sample('full', tracer, nil, round: 'prime')
      raise EvidenceError, "#{tracer} prime run is invalid: #{row.fetch(:errors).join('; ')}" unless row[:valid]

      seed = File.join(@directory, 'seeds', tracer)
      FileUtils.mkdir_p(seed)
      TRACERS.fetch(tracer).fetch(:outputs).each do |relative|
        source = File.join(@workspace.path, relative)
        FileUtils.cp_r(source, seed) if File.exist?(source)
      end
      @seeds[tracer] = seed
      @state[:seeds][tracer] = { path: seed, identity: identity(seed), cache_examples: row.fetch(:cache_examples) }
    end

    def cells
      controls = (@options.fetch(:cases) & CONTROL_CASES).map { |kase| [kase, nil, nil] }
      controls + @options.fetch(:tracers).product(tracer_cases).flat_map do |tracer, kase|
        case kase
        when 'changed' then changes.map { |change| ['changed', tracer, change.fetch('name')] }
        when 'fault' then [['fault', tracer, 'fault']]
        else [[kase, tracer, nil]]
        end
      end
    end

    def rounds
      random = Random.new(@options.fetch(:seed))
      order = 0
      @options.fetch(:repetitions).times do |round|
        cells.shuffle(random: random).each do |kase, tracer, variant|
          order += 1
          sample(kase, tracer, variant, round: round, order: order)
        end
      end
    end

    def sample(kase, tracer, variant, round:, order: nil)
      @workspace.reset
      restore_seconds = restore_seed(kase, tracer)
      mutate(kase, tracer, variant)
      directory = File.join(@directory, 'runs', [kase, tracer, variant, round].compact.join('-'))
      FileUtils.mkdir_p(File.join(directory, 'results'))
      row = invoke(kase, tracer, variant, directory)
      row.merge!(round: round, order: order, external_seed_restore_seconds: restore_seconds)
      Validation.new(row, oracle_for(kase, variant), processes: @runner.expected_processes(@spec),
                                                     tracer_version: tracer_version(tracer)).apply
      @record.call(row)
      announce(row)
      row
    end

    def announce(row)
      state = row[:valid] ? '' : " INVALID #{row[:errors].join('; ')}"
      warn format('%<project>s %<round>s %<case>s %<tracer>s %<variant>s: %<wall>.1fs %<executed>d examples%<state>s',
                  project: @workspace.name, round: row[:round], case: row[:case], tracer: row[:tracer] || '-',
                  variant: row[:variant] || '-', wall: row[:wall_seconds], executed: row[:executed], state: state)
    end

    def oracle_for(kase, variant)
      return nil if kase == 'plain' && @oracles.empty?

      @oracles.fetch(variant || 'base', nil)
    end

    def tracer_version(tracer)
      case tracer
      when 'testsift' then @runner.testsift
      when 'rspec-tracer' then { source: 'rubygems', version: RSPEC_TRACER_VERSION }
      end
    end

    def restore_seed(kase, tracer)
      return 0.0 unless tracer && kase != 'full'

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      seed = @seeds.fetch(tracer)
      Dir.children(seed).each { |entry| FileUtils.cp_r(File.join(seed, entry), @workspace.path) }
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    end

    def mutate(kase, tracer, variant)
      if variant == 'fault'
        fault = @spec.fetch('fault')
        @workspace.replace(fault.fetch('path'), fault.fetch('from'), fault.fetch('to'))
      elsif variant
        @workspace.apply_patch(*patch(changes.find { |change| change.fetch('name') == variant }))
      elsif kase == 'invalidated'
        @workspace.append(TRACERS.fetch(tracer).fetch(:config), INVALIDATION)
      end
    end

    def patch(change)
      @patches[change.fetch('name')] ||= begin
        diff, paths = @workspace.patch_for(change)
        path = File.join(@directory, 'patches', "#{change.fetch('name')}.patch")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, diff)
        [path, paths]
      end
    end

    def invoke(kase, tracer, variant, directory)
      env = { 'RUBYOPT' => "-r#{BOOT}", 'OSS_RESULTS' => File.join(directory, 'results'),
              'OSS_TRACER' => tracer, 'OSS_COVERAGE' => kase == 'coverage_control' ? COVERAGE_MODES : nil }
      argv = Host.timed(command, File.join(directory, 'time.txt'))
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      output, status = Open3.capture2e(@workspace.env(env), *argv, chdir: @workspace.path, unsetenv_others: true)
      wall = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      File.write(File.join(directory, 'output.log'), output)
      measurements(directory, tracer).merge(
        project: @workspace.name, suite: @options.fetch(:suite), case: kase, tracer: tracer, variant: variant,
        command: argv, env: @workspace.project_env.merge(env.compact), exit_code: status.exitstatus,
        wall_seconds: wall, artifact_directory: directory
      )
    end

    def command
      substitutions = { '{seed}' => @options.fetch(:seed).to_s, '{workers}' => @runner.workers(@spec).to_s }
      @runner.runner(@spec).fetch('command').map { |part| part.gsub(/\{\w+\}/) { |key| substitutions.fetch(key) } } +
        @spec.fetch('suites').fetch(@options.fetch(:suite))
    end

    def measurements(directory, tracer)
      processes = Dir.glob(File.join(directory, 'results', 'process.*.json')).map { |path| JSON.parse(File.read(path)) }
      examples = processes.flat_map { |process| process.fetch('examples', []) }
      File.write(File.join(directory, 'examples.json'), JSON.generate(examples))
      resources(directory).merge(
        processes: processes.map { |process| process.except('examples') },
        executed: examples.size, unique_executed: examples.map(&:first).uniq.size,
        failures: examples.select { |_, status| status == 'failed' }.map(&:first).sort,
        allocations: processes.sum { |process| process.fetch('allocations', 0) },
        **cache_measurements(tracer)
      )
    end

    def resources(directory)
      time = File.join(directory, 'time.txt')
      File.exist?(time) ? Host.resources(time) : {}
    end

    def cache_measurements(tracer)
      return { cache_bytes: 0, report_bytes: 0, cache_examples: nil, duplicate_examples: nil } unless tracer

      cache, report, coverage = TRACERS.fetch(tracer).fetch(:outputs).map { |dir| File.join(@workspace.path, dir) }
      { cache_bytes: bytes(cache), report_bytes: bytes(report) + bytes(coverage), **cache_contents(cache) }
    end

    def cache_contents(cache)
      manifest = File.join(cache, 'last_run.json')
      return { cache_examples: 0, duplicate_examples: nil } unless File.file?(manifest)

      run = File.join(cache, JSON.parse(File.read(manifest)).fetch('run_id'))
      duplicates = File.join(run, 'duplicate_examples.json')
      { cache_examples: JSON.parse(File.read(File.join(run, 'all_examples.json'))).size,
        duplicate_examples: File.file?(duplicates) ? JSON.parse(File.read(duplicates)).values.sum(&:size) : 0 }
    end

    def files(directory)
      Dir.glob(File.join(directory, '**', '*'), File::FNM_DOTMATCH).select { |path| File.file?(path) }.sort
    end

    def bytes(directory)
      files(directory).sum { |path| File.size(path) }
    end

    def identity(directory)
      Digest::SHA256.hexdigest(files(directory).map do |path|
        "#{path.delete_prefix(directory)} #{Digest::SHA256.file(path)}"
      end.join("\n"))
    end
  end
end
