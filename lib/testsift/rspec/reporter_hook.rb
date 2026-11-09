# frozen_string_literal: true

module TestSift
  # Internal RSpec — see {TestSift} for the user-facing surface.
  # @api private
  module RSpec
    # Prepended onto `RSpec::Core::Reporter` by
    # `TestSift::RSpec::Installation.install!`. Replaces the 1.x
    # `TestSift::RSpecReporter` singleton-class prepend.
    #
    # Forwards RSpec's example lifecycle notifications into the engine,
    # then chains to `super`. Every callback is no-op when either:
    #   - the engine isn't set up (start never called, graceful degrade)
    #   - the example carries no `:testsift_example_id` metadata
    #     (it was partitioned into `ignore_spec_files` by RunnerHook, so
    #     the tracer treats it as invisible)
    #
    # The per-example coverage peek+diff sequence (peek before, peek
    # after) runs through Engine#example_started + Engine#example_finished
    # only. 2.0 retired the legacy CoverageReporter that previously
    # peeked a second time per example; coverage.json emission now
    # consumes the Engine's per-example deltas + a single finalize-time
    # peek through Tracker::CoverageAdapter#peek_unfiltered.
    module ReporterHook
      # Internal method on the tracer pipeline.
      # @api private
      def example_started(_example)
        TestSift.engine&.example_started

        super
      end

      # Internal method on the tracer pipeline.
      # @api private
      def example_finished(example)
        engine = TestSift.engine
        if engine
          example_id = example.metadata[:testsift_example_id]
          engine.example_finished(example_id) if example_id
        end

        super
      end

      # Internal method on the tracer pipeline.
      # @api private
      def example_passed(example)
        _testsift_status(example, :on_example_passed)

        super
      end

      # Internal method on the tracer pipeline.
      # @api private
      def example_failed(example)
        _testsift_status(example, :on_example_failed)

        super
      end

      # Internal method on the tracer pipeline.
      # @api private
      def example_pending(example)
        _testsift_status(example, :on_example_pending)

        super
      end

      private

      # Internal method on the tracer pipeline.
      # @api private
      def _testsift_status(example, method)
        engine = TestSift.engine
        return unless engine

        example_id = example.metadata[:testsift_example_id]
        return unless example_id

        result = example.execution_result
        engine.public_send(method, example_id, {
                             started_at: result.started_at.utc,
                             finished_at: result.finished_at.utc,
                             run_time: result.run_time,
                             status: result.status.to_s
                           })
      end
    end
  end
end
