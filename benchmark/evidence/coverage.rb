# frozen_string_literal: true

require 'coverage'
require 'json'
require 'tmpdir'
require 'fileutils'

class CoverageEvidence
  def initialize
    @files = Integer(ENV.fetch('FILES', '500'))
    @branch_sites = Integer(ENV.fetch('BRANCH_SITES', '60'))
    @iterations = Integer(ENV.fetch('ITERATIONS', '20'))
    @touched = Integer(ENV.fetch('TOUCHED', '1'))
    @mode = ENV.fetch('MODE', 'lines')
    raise ArgumentError, 'unknown mode' unless %w[off lines branches tracepoint].include?(@mode)
    raise ArgumentError, 'positive sizes required' unless [@files, @branch_sites, @iterations,
                                                           @touched].all?(&:positive?)
    raise ArgumentError, 'TOUCHED must not exceed FILES' if @touched > @files

    @samples = Hash.new { |hash, key| hash[key] = [] }
  end

  def run
    Dir.mktmpdir('testsift-real-coverage') do |root|
      prepare(root)
      @iterations.times { iteration }
      @tracepoint&.disable
      puts JSON.generate(result)
    end
  end

  private

  def source(index)
    body = "value += 1 if x >= 0\n" * @branch_sites
    "module EvidenceWorkload#{index}\ndef self.call(x)\nvalue = 0\n#{body}value\nend\nend\n"
  end

  def prepare(root)
    paths = Array.new(@files) do |index|
      path = File.join(root, "workload_#{index}.rb")
      File.write(path, source(index))
      path
    end
    start_collector(root)
    paths.each { |path| load path }
    @workloads = Array.new(@files) { |index| Object.const_get("EvidenceWorkload#{index}") }
    @active = @workloads.first(@touched)
    execute(@workloads)
  end

  def start_collector(root)
    if @mode == 'tracepoint'
      @observed = {}
      prefix = "#{root}/"
      @tracepoint = TracePoint.new(:line) do |event|
        path = event.path
        @observed[path] = true if path.start_with?(prefix)
      end
      @tracepoint.enable
    elsif @mode != 'off'
      Coverage.start(lines: true, branches: @mode == 'branches')
    end
  end

  def measure(label)
    allocations = GC.stat(:total_allocated_objects)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    value = yield
    @samples[label] << { seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
                         allocations: GC.stat(:total_allocated_objects) - allocations }
    value
  end

  def execute(workloads = @active)
    workloads.each do |workload|
      raise 'generated code returned wrong result' unless workload.call(1) == @branch_sites
    end
  end

  def line_array(entry)
    entry.is_a?(Hash) ? entry.fetch(:lines) : entry
  end

  def iteration
    case @mode
    when 'off'
      measure('execution') { execute }
    when 'tracepoint'
      measure('file_set_reset') { @observed.clear }
      measure('execution') { execute }
      paths = measure('file_set_result') { @observed.keys }
      raise "wrong observed-file count: #{paths.size}" unless paths.size == @touched
    else
      coverage_iteration
    end
  end

  def coverage_iteration
    before = measure('snapshot') { Coverage.peek_result }
    measure('execution') { execute }
    after = measure('snapshot') { Coverage.peek_result }
    changed = measure('line_scan') do
      after.count { |path, stats| line_array(before.fetch(path)) != line_array(stats) }
    end
    raise "wrong changed-file count: #{changed}" unless changed == @touched

    measure('keys_from_existing_snapshot') { after.keys }
    measure('extra_snapshot_for_keys') { Coverage.peek_result.keys }
    compare_normalization(after)
    @coverage_files = after.size
    @line_slots = after.values.sum { |entry| line_array(entry).length }
  end

  def compare_normalization(raw)
    enumerable = measure('normalize_each_with_object') do
      raw.each_with_object({}) { |(path, entry), result| result[path] = line_array(entry) }
    end
    pairs = measure('normalize_each_pair') do
      result = {}
      raw.each_pair { |path, entry| result[path] = line_array(entry) }
      result
    end
    raise 'normalization results differ' unless enumerable == pairs
  end

  def percentile(samples, key, fraction)
    values = samples.map { |sample| sample.fetch(key) }.sort
    values.fetch((values.size * fraction).ceil - 1)
  end

  def result
    { ruby: RUBY_DESCRIPTION, files: @files, touched: @touched,
      branch_sites_per_file: @branch_sites, iterations: @iterations,
      mode: @mode, coverage_files: @coverage_files, line_slots: @line_slots, samples: @samples,
      measurements: @samples.transform_values do |samples|
        { count: samples.size, p50_seconds: percentile(samples, :seconds, 0.5),
          p95_seconds: percentile(samples, :seconds, 0.95),
          p50_allocations: percentile(samples, :allocations, 0.5) }
      end }
  end
end

CoverageEvidence.new.run if $PROGRAM_NAME == __FILE__
