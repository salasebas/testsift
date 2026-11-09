# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'testsift/engine'

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.shared_context 'with engine configuration' do
  let(:tmp_base) { Dir.mktmpdir }
  let(:root) { File.join(tmp_base, 'project').tap { |p| FileUtils.mkdir_p(p) } }
  let(:cache_path) { File.join(tmp_base, 'cache') }
  let(:logger) { instance_double(TestSift::Logger, debug: nil, info: nil, warn: nil, error: nil) }
  let(:configuration) { stub_configuration }
  let(:current_schema) { TestSift::Storage::Schema::CURRENT }

  before do
    write_project_file('lib/a.rb', "module A; VALUE = 1; end\n")
    write_project_file('lib/b.rb', "require_relative 'a'\nUSER = A::VALUE\n")
  end

  after do
    TestSift::Tracker::IOHooks.uninstall
    TestSift::Tracker::IOHooks.clear_bucket
    FileUtils.rm_rf(tmp_base) if tmp_base
  end

  def write_project_file(rel, contents = "x\n")
    path = File.join(root, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
    path
  end

  def stub_configuration(overrides = {})
    defaults = {
      root: root, cache_path: cache_path, logger: logger,
      filters: [], declared_globs: [], tracked_env_names: [],
      run_all_examples: false, transitive_load_tracking: false,
      rails?: false, track_ar_schema_notifications?: false,
      cache_retention_local_count: nil,
      cache_size_warn_per_file_mb: nil, cache_size_warn_total_mb: nil,
      storage_backend: :json, storage_backend_opts: {}
    }
    double(**defaults, **overrides).tap do |config|
      allow(config).to receive(:freeze_declared_globs!)
    end
  end

  # The example-start boundary reads #peek; the finish boundary reads
  # #peek_with_paths so loaded-file tracking shares that snapshot.
  def stub_example_snapshots(engine, before, after)
    allow(engine.coverage_adapter).to receive_messages(peek: before, peek_with_paths: [after, after.keys])
  end

  def build_tracker(configuration_override = configuration)
    TestSift::Engine.new(configuration: configuration_override)
  end

  def build_example(example_id, file_name = '/spec/thing_spec.rb', line = 1)
    {
      example_id: example_id,
      file_name: file_name,
      line_number: line,
      rerun_file_name: file_name,
      rerun_line_number: line,
      full_description: "Example #{example_id}",
      description: "Example #{example_id}",
      example_group: 'Thing',
      shared_group: []
    }
  end

  def build_execution_result(status:, run_time: 0.01)
    now = Time.now
    { started_at: now.utc, finished_at: (now + run_time).utc, run_time: run_time, status: status.to_s }
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
