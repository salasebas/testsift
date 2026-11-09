# frozen_string_literal: true

require 'coverage'
require 'json'
require 'fileutils'

module Evidence
  START = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  ALLOCATIONS = GC.stat(:total_allocated_objects)
  JSON_LABELS = %w[json_decode json_encode].freeze
  CACHE_LABELS = %w[cache_load cache_decode cache_save].freeze
  @metrics = Hash.new { |hash, key| hash[key] = { calls: 0, seconds: 0.0, allocations: 0 } }
  @stack = []

  def self.measure(label)
    return yield if @finished

    label = json_context(label) if JSON_LABELS.include?(label)
    frame = [label, Process.clock_gettime(Process::CLOCK_MONOTONIC), GC.stat(:total_allocated_objects), 0.0, 0]
    @stack << frame
    begin
      yield
    ensure
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - frame[1]
      allocated = GC.stat(:total_allocated_objects) - frame[2]
      @stack.pop
      metric = @metrics[label]
      metric[:calls] += 1
      metric[:seconds] += elapsed - frame[3]
      metric[:allocations] += allocated - frame[4]
      unless @stack.empty?
        @stack.last[3] += elapsed
        @stack.last[4] += allocated
      end
    end
  end

  def self.json_context(label)
    cache = @stack.any? { |frame| CACHE_LABELS.include?(frame[0]) }
    cache ? "cache_#{label}" : label
  end

  def self.wrap(target, method, label)
    hook = Module.new do
      define_method(method) do |*args, **kwargs, &block|
        Evidence.measure(label) { super(*args, **kwargs, &block) }
      end
    end
    target.prepend(hook)
  end

  # Engines before the shared example-boundary snapshot named this step peek_normalized.
  def self.normalization_method
    adapter = RSpecTracer::Tracker::CoverageAdapter
    adapter.private_method_defined?(:normalize) ? :normalize : :peek_normalized
  end

  def self.observer_targets
    {
      RSpecTracer::Tracker::CoverageAdapter => {
        compute_diff: 'dependency_delta', normalization_method => 'coverage_normalize'
      },
      RSpecTracer::Tracker::LoadedFilesTracker => {
        capture_boot_set!: 'loaded_attribution', loaded_set_inputs: 'loaded_attribution',
        stop_example: 'loaded_attribution'
      },
      RSpecTracer::Tracker::FileDigest.singleton_class => { compute: 'stat_hash' },
      RSpecTracer::Tracker::DeclaredGlobs => { walk: 'declared_globs' },
      RSpecTracer::Tracker::NewFileDetector => { new_files: 'new_files' },
      RSpecTracer::Tracker::DependencyGraph => { register_example: 'graph', examples_depending_on: 'graph' },
      RSpecTracer::Tracker::Filter.singleton_class => { select: 'selection' }
    }
  end

  def self.engine_targets
    {
      RSpecTracer::Engine => {
        setup: 'setup', example_started: 'example_boundary', example_finished: 'example_boundary',
        record_coverage_delta: 'report_delta', attribute_to_example: 'file_attribution',
        compute_change_set: 'change_detection', build_snapshot: 'snapshot_build', finalize: 'finalize'
      },
      RSpecTracer.singleton_class => {
        emit_reporters: 'reports', emit_coverage_json: 'coverage_report', run_exit_tasks: 'exit_tasks'
      },
      RSpecTracer::RSpec::ParallelTests.singleton_class => {
        finalize!: 'worker_finalize', merge_snapshot!: 'worker_merge', merge_coverage!: 'worker_merge'
      }
    }
  end

  def self.storage_targets
    {
      RSpecTracer::Storage::JsonBackend => {
        load_graph: 'cache_load', save_graph: 'cache_save', read_field: 'cache_decode'
      },
      JSON.singleton_class => { parse: 'json_decode', generate: 'json_encode', pretty_generate: 'json_encode' },
      File.singleton_class => { stat: 'filesystem_stat' },
      Digest::SHA256.singleton_class => { file: 'sha256' },
      Coverage.singleton_class => { peek_result: 'coverage_snapshot' }
    }
  end

  def self.install_profile
    observer_targets.merge(engine_targets).merge(storage_targets).each do |target, methods|
      methods.each do |method, label|
        raise "profile target missing: #{target}##{method}" unless target.method_defined?(method) ||
          target.private_method_defined?(method)

        wrap(target, method, label)
      end
    end
  end

  def self.coverage_dimensions
    coverage = ENV['EVIDENCE_PROFILE'] == '1' && Coverage.running? ? Coverage.peek_result : {}
    project = coverage.select { |path, _| path.start_with?("#{Dir.pwd}/") }
    app = project.select { |path, _| path.start_with?("#{Dir.pwd}/app/") }
    { coverage_files: coverage.size,
      coverage_line_slots: coverage.values.sum { |entry| line_array(entry).length },
      project_coverage_files: project.size,
      project_executed_lines: executed_lines(project), app_executed_lines: executed_lines(app) }
  end

  def self.executed_lines(coverage)
    coverage.values.sum { |entry| line_array(entry).count { |hits| hits&.positive? } }
  end

  def self.line_array(entry)
    entry.is_a?(Hash) ? entry.fetch(:lines, []) : entry
  end

  def self.finish
    @finished = true
    payload = {
      pid: Process.pid, worker: ENV.fetch('TEST_ENV_NUMBER', nil), ruby: RUBY_DESCRIPTION,
      gems: Gem.loaded_specs.transform_values { |spec| spec.version.to_s },
      elapsed_inside: Process.clock_gettime(Process::CLOCK_MONOTONIC) - START,
      allocations: GC.stat(:total_allocated_objects) - ALLOCATIONS, gc: GC.stat,
      discovery: @discovery, metrics: @metrics
    }.merge(coverage_dimensions)
    path = "#{ENV.fetch('EVIDENCE_TELEMETRY')}.#{Process.pid}.json"
    File.write(path, JSON.generate(payload))
  end

  def self.export_branches
    project = Coverage.peek_result.select { |path, _| path.start_with?("#{Dir.pwd}/") }
    FileUtils.mkdir_p('evidence_branch_report')
    File.write("evidence_branch_report/#{Process.pid}.json", JSON.generate(project))
  end

  def self.dependency_only
    RSpecTracer::Engine.prepend(Module.new do
      def record_coverage_delta(*)
        nil
      end
    end)
    RSpecTracer.singleton_class.prepend(Module.new do
      def emit_coverage_json
        nil
      end
    end)
  end

  def self.share_loaded_snapshot
    Coverage.singleton_class.prepend(Module.new do
      def peek_result
        result = super
        Evidence.instance_variable_set(:@latest_coverage_keys, result.keys)
        result
      end
    end)
    RSpecTracer::Tracker::LoadedFilesTracker.prepend(Module.new do
      def stop_example(*)
        original = @peek
        @peek = -> { Evidence.instance_variable_get(:@latest_coverage_keys) }
        super
      ensure
        @peek = original
      end
    end)
  end
end

at_exit { Evidence.finish }
at_exit do
  if ENV['EVIDENCE_MODE'] == 'branches' && Coverage.running?
    if ENV['EVIDENCE_PROFILE'] == '1'
      Evidence.measure('branch_report') { Evidence.export_branches }
    else
      Evidence.export_branches
    end
  end
end

mode = ENV.fetch('EVIDENCE_MODE')
Coverage.start(lines: true, branches: mode == 'branches') unless mode == 'plain'

if ENV['EVIDENCE_TRACER'] == '1'
  require 'rspec_tracer'
  Evidence.dependency_only if mode == 'dependency'
  Evidence.share_loaded_snapshot if ENV['EVIDENCE_VARIANT'] == 'share_snapshot'
  Evidence.install_profile if ENV['EVIDENCE_PROFILE'] == '1'
end

require 'rspec/core'
discovery_observer = Module.new do
  def run_specs(groups)
    Evidence.instance_variable_set(:@discovery, RSpec.world.example_count)
    super
  end
end
discovery_target = ENV['EVIDENCE_TRACER'] == '1' ? RSpecTracer::RSpec::RunnerHook : RSpec::Core::Runner
discovery_target.prepend(discovery_observer)
