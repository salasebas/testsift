# frozen_string_literal: true

module TestSift
  class Engine
    module SnapshotBuilder
      private

      # Internal method on the tracer pipeline.
      # @api private
      def build_snapshot
        run_id = Digest::MD5.hexdigest(@all_examples.keys.sort.to_json)
        @run_id = run_id

        TestSift::Storage::Snapshot.new(
          schema_version: TestSift::Storage::Schema::CURRENT,
          run_id: run_id,
          all_examples: @all_examples,
          duplicate_examples: duplicates_for_snapshot,
          interrupted_examples: @registry.ids_with_status(:interrupted),
          flaky_examples: @registry.ids_with_status(:flaky),
          failed_examples: @registry.ids_with_status(:failed),
          pending_examples: @registry.ids_with_status(:pending),
          skipped_examples: @registry.ids_with_status(:skipped),
          all_files: all_files_by_name,
          dependency: dependency_by_name,
          reverse_dependency: reverse_dependency_by_name,
          examples_coverage: merge_examples_coverage_with_previous,
          boot_set: @loaded_files_tracker.boot_set_digest_snapshot,
          wsi_snapshot: @whole_suite_invalidators.digest_snapshot,
          env_snapshot: env_snapshot_for_persistence,
          env_dependency: env_dependency_for_persistence,
          cache_hit_reason: @filtered_examples.values.tally,
          filtered_examples: @filtered_examples
        )
      end

      # Merge the current run's per-example coverage with the previous
      # run's. Re-run examples contribute their freshly-computed map
      # (record_coverage_delta overwrote per-line strengths, so
      # @examples_coverage[id] is the authoritative new coverage).
      # Skipped examples don't appear in @examples_coverage, so the
      # prev map carries them forward unchanged. Previously in
      # seed_state_from_previous; moved here so large caches don't
      # pay the full examples_coverage materialization cost at setup
      # time. Preserves 1.x semantics: the saved map is the union of
      # (prev minus this-run's keys) + this-run's entries.
      def merge_examples_coverage_with_previous
        merged = {}
        if @previous_snapshot
          prev = @previous_snapshot.examples_coverage
          if prev.is_a?(Hash)
            prev.each { |id, cov| merged[id] = cov unless @examples_coverage.key?(id) }
          end
        end
        @examples_coverage.each { |id, cov| merged[id] = cov }
        merged
      end

      # Snapshot only the env keys THIS run tracked - persisting keys
      # that stopped being tracked (user removed `tracks: env: ...`
      # between runs) would pin stale digests in the cache. Missing
      # keys on the next load just trigger a one-time re-run for any
      # example that reintroduces them, which is the correct behavior.
      def env_snapshot_for_persistence
        return {} if @env_snapshot.nil? || @tracked_env_names.empty?

        @env_snapshot.digest_snapshot(@tracked_env_names)
      end

      # Project the per-example `@tracks_env` map (Set<env_name> per
      # example_id) into a JSON-friendly Hash[id => sorted Array] for
      # persistence. Reporters consume this to render the env-
      # dependency view on the Examples Dependency report. Empty sets
      # drop out so the on-disk map stays narrow. Sort keeps the output
      # deterministic for downstream diffs and golden tests.
      def env_dependency_for_persistence
        result = {}
        @tracks_env.each do |example_id, names|
          next if names.nil? || names.empty?

          result[example_id] = names.to_a.sort
        end
        result
      end

      # Internal method on the tracer pipeline.
      # @api private
      def duplicates_for_snapshot
        @duplicate_examples.select { |_, entries| entries.count > 1 }
      end

      # Internal method on the tracer pipeline.
      # @api private
      def all_files_by_name
        @all_files.each_with_object({}) do |(_, meta), acc|
          acc[meta[:file_name]] = meta
        end
      end

      # Internal method on the tracer pipeline.
      # @api private
      def dependency_by_name
        @graph.example_ids.to_h do |id|
          [id, @graph.paths_for(id).to_set { |p| path_to_file_name(p) }]
        end
      end

      # Internal method on the tracer pipeline.
      # @api private
      def reverse_dependency_by_name
        @graph.reverse_dependency_hash.each_with_object({}) do |(path, ids), acc|
          acc[path_to_file_name(path)] = ids.to_set
        end
      end
    end
  end
end
