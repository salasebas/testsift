# frozen_string_literal: true

require 'json'
require 'set'

module OSSBenchmark
  class Validation
    COMPLETE_CASES = %w[plain coverage_control full invalidated].freeze

    def self.executed_ids(row)
      JSON.load_file(File.join(row.fetch(:artifact_directory), 'examples.json')).to_set(&:first)
    end

    def initialize(row, oracle, processes:, tracer_version:)
      @row = row
      @oracle = oracle
      @processes = processes
      @tracer = row[:tracer]
      @expected = tracer_version
      @errors = []
    end

    def apply
      check_awake
      check_process_count
      check_tracer_loaded if @tracer
      check_exit
      check_oracle if @oracle
      @row[:errors] = @errors
      @row[:valid] = @errors.empty?
    end

    private

    def check_awake
      slept = @row[:slept_seconds].to_f
      @errors << "host slept #{slept.round(1)} s during the run" if slept > 1
    end

    def check_process_count
      telemetry = @row.fetch(:processes)
      unless telemetry.size == @processes
        @errors << "#{telemetry.size} RSpec processes reported, expected #{@processes}"
      end
      @errors << 'an RSpec process did not finish' unless telemetry.all? { |process| process['finished'] }
      @errors << 'an example ran in more than one process' unless @row[:executed] == @row[:unique_executed]
    end

    def check_tracer_loaded
      @row.fetch(:processes).each do |process|
        @errors << "#{@tracer} did not start in pid #{process['pid']}" unless process['tracer_started']
        next if expected_tracer?(process)

        @errors << "#{@tracer} loaded #{process['tracer_version']} from #{process['tracer_path']}"
      end
    end

    def expected_tracer?(process)
      process['tracer_version'] == @expected.fetch(:version) &&
        (@expected[:path].nil? || process['tracer_path'] == @expected[:path])
    end

    def check_exit
      expected = @row.fetch(:failures).empty? ? 0 : 1
      return if @row.fetch(:exit_code) == expected

      @errors << "exit #{@row[:exit_code]} with #{@row[:failures].size} failing examples"
    end

    def check_oracle
      ids = self.class.executed_ids(@row)
      phantom = ids - @oracle.fetch(:ids)
      @errors << "#{phantom.size} examples are absent from the plain oracle" unless phantom.empty?
      unexecuted = @oracle.fetch(:ids) - ids
      @row.merge!(total: @oracle.fetch(:total), unexecuted: unexecuted.size,
                  selected_ratio: @row.fetch(:executed).fdiv(@oracle.fetch(:total)))
      check_complete(unexecuted) if COMPLETE_CASES.include?(@row.fetch(:case))
      check_cache if @tracer
      check_failures(ids)
    end

    def check_complete(unexecuted)
      return if unexecuted.empty?
      return if @tracer && unexecuted.size == @row[:duplicate_examples].to_i

      @errors << "#{unexecuted.size} oracle examples did not run " \
                 "(tracer reported #{@row[:duplicate_examples].inspect} duplicates)"
    end

    # A cache may keep identities of examples that a change deleted or moved;
    # only a cache missing trackable examples (for example a lost worker) is
    # incomplete.
    def check_cache
      expected = @oracle.fetch(:total) - @row[:duplicate_examples].to_i
      @row[:stale_cache_examples] = @row[:cache_examples].to_i - expected
      return if @row[:cache_examples].to_i >= expected

      @errors << "cache holds #{@row[:cache_examples].inspect} examples, expected at least #{expected}"
    end

    def check_failures(ids)
      oracle_failures = @oracle.fetch(:failures)
      selected, missed = oracle_failures.partition { |id| ids.include?(id) }
      @row.merge!(oracle_failures: oracle_failures.size, missed_failures: missed,
                  status_mismatches: (selected - @row[:failures]) | (@row[:failures] - oracle_failures))
    end
  end
end
