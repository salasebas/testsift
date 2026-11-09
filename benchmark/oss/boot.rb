# frozen_string_literal: true

require 'English'
require 'json'

# Preloaded through RUBYOPT into every Ruby process an OSS project's runner
# starts, in every benchmark case, so plain and traced runs pay the same
# preload. It acts only in processes that execute RSpec examples: `rspec`
# itself, or `bundle exec rspec`, which Bundler loads into its own process.
#
# In those processes it starts the requested tracer or the Coverage control
# before the project loads, records which examples ran through an RSpec
# reporter listener, and writes one telemetry file when the process exits.
module OSSBenchmark
  module Boot
    START = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    PID = Process.pid
    ALLOCATIONS = GC.stat(:total_allocated_objects)
    TRACERS = {
      'testsift' => { gem: 'testsift', require: 'testsift', constant: 'TestSift' },
      'rspec-tracer' => { gem: 'rspec-tracer', require: 'rspec_tracer', constant: 'RSpecTracer' }
    }.freeze

    # Collects executed examples. Examples a tracer filters out never reach
    # the reporter, so this list is what actually ran.
    class Listener
      attr_reader :examples

      def initialize
        @examples = []
      end

      def example_finished(notification)
        example = notification.example
        @examples << [example.id, example.execution_result.status.to_s]
      end
    end

    module_function

    def rspec_process?
      program = File.basename($PROGRAM_NAME)
      return true if program == 'rspec'

      program == 'bundle' && ARGV[0] == 'exec' && File.basename(ARGV[1].to_s) == 'rspec'
    end

    def start
      @listener = Listener.new
      @telemetry = { pid: Process.pid, test_env_number: ENV.fetch('TEST_ENV_NUMBER', nil), argv: ARGV.dup,
                     program: $PROGRAM_NAME, tracer: ENV.fetch('OSS_TRACER', nil),
                     coverage: ENV.fetch('OSS_COVERAGE', nil) }
      at_exit { finish }
      require 'bundler/setup'
      start_coverage if @telemetry[:coverage]
      start_tracer if @telemetry[:tracer]
      require 'rspec/core'
      listener = @listener
      RSpec.configure do |config|
        config.before(:suite) { config.reporter.register_listener(listener, :example_finished) }
      end
    end

    def start_coverage
      require 'coverage'
      Coverage.start(@telemetry.fetch(:coverage).split(',').to_h { |mode| [mode.to_sym, true] })
    end

    def start_tracer
      tracer = TRACERS.fetch(@telemetry.fetch(:tracer))
      require tracer.fetch(:require)
      spec = Gem.loaded_specs.fetch(tracer.fetch(:gem))
      @telemetry[:tracer_version] = spec.version.to_s
      @telemetry[:tracer_path] = spec.full_gem_path
      Object.const_get(tracer.fetch(:constant)).start
      @telemetry[:tracer_started] = true
    end

    # Registered before the tracer's own at_exit hooks, so it runs after them
    # and its counters include cache persistence and report generation.
    # Processes the suite forks inherit this hook; only the original writes.
    def finish
      return unless Process.pid == PID

      status = $ERROR_INFO.is_a?(SystemExit) ? $ERROR_INFO.status : nil
      @telemetry.merge!(finished: true, exit_status: status, examples: @listener.examples,
                        allocations: GC.stat(:total_allocated_objects) - ALLOCATIONS,
                        elapsed_inside: Process.clock_gettime(Process::CLOCK_MONOTONIC) - START)
      File.write(File.join(ENV.fetch('OSS_RESULTS'), "process.#{Process.pid}.json"), JSON.generate(@telemetry))
    end
  end
end

OSSBenchmark::Boot.start if ENV['OSS_RESULTS'] && OSSBenchmark::Boot.rspec_process?
