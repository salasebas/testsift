# frozen_string_literal: true

require 'fileutils'
require 'logger'
require 'tmpdir'
require 'testsift/engine'

raise 'RSpec loaded with the engine' if defined?(RSpec)

EngineConfiguration = Struct.new(
  :root, :cache_path, :logger, :filters, :declared_globs, :tracked_env_names,
  :run_all_examples, :transitive_load_tracking, :storage_backend, :storage_backend_opts,
  :cache_retention_local_count, :cache_size_warn_per_file_mb, :cache_size_warn_total_mb,
  keyword_init: true
) do
  def freeze_declared_globs!
    declared_globs.freeze
  end

  def rails?
    false
  end
end

def assert_engine(condition, message)
  raise message unless condition
end

def register(engine, id)
  engine.register_example(example_id: id, description: id, file_name: '/test.rb')
end

def complete(engine, id, path)
  engine.example_started
  File.read(path)
  engine.example_finished(id)
  now = Time.now.utc
  engine.on_example_passed(id, started_at: now, finished_at: now, run_time: 0.0, status: 'passed')
end

Dir.mktmpdir('neutral-engine') do |root|
  path = File.join(root, 'input.yml')
  File.write(path, 'original')
  configuration = EngineConfiguration.new(
    root: root, cache_path: File.join(root, 'cache'), logger: Logger.new(File::NULL),
    filters: [], declared_globs: [], tracked_env_names: [], run_all_examples: false,
    transitive_load_tracking: false, storage_backend: :json, storage_backend_opts: {}
  )

  cold = TestSift::Engine.new(configuration: configuration).setup
  register(cold, 'plain:test')
  assert_engine(cold.run_example?('plain:test'), 'new test must run')
  complete(cold, 'plain:test', path)
  snapshot = cold.finalize
  assert_engine(snapshot.dependency.fetch('plain:test').include?('/input.yml'), 'I/O dependency missing')
  assert_engine(snapshot.all_examples.fetch('plain:test').dig(:execution_result, :status) == 'passed',
                'outcome missing')

  warm = TestSift::Engine.new(configuration: configuration).setup
  register(warm, 'plain:test')
  assert_engine(!warm.run_example?('plain:test'), 'unchanged passing test must be skipped')
  warm.on_example_skipped('plain:test')
  warm.finalize

  worker_configuration = configuration.dup
  worker_configuration.cache_path = File.join(root, 'worker-cache')
  worker = TestSift::Engine.new(configuration: worker_configuration, read_cache_path: configuration.cache_path).setup
  register(worker, 'plain:test')
  assert_engine(!worker.run_example?('plain:test'), 'explicit parent cache must select like a warm run')
  worker.on_example_skipped('plain:test')
  worker.finalize
  assert_engine(File.file?(File.join(worker_configuration.cache_path, 'last_run.json')), 'worker cache not saved')

  File.write(path, 'changed')
  changed = TestSift::Engine.new(configuration: configuration).setup
  register(changed, 'plain:test')
  assert_engine(changed.run_example?('plain:test'), 'changed dependency must select the test')
  assert_engine(changed.run_example_reason('plain:test') == 'Files changed', 'wrong change reason')
  complete(changed, 'plain:test', path)
  register(changed, 'plain:unfinished')
  changed.finalize

  interrupted = TestSift::Engine.new(configuration: configuration).setup
  register(interrupted, 'plain:unfinished')
  assert_engine(interrupted.run_example?('plain:unfinished'), 'unfinished test must run again')
  assert_engine(interrupted.run_example_reason('plain:unfinished') == 'Interrupted previously',
                'wrong interruption reason')
  interrupted.finalize

  assert_engine(!defined?(RSpec), 'RSpec loaded during the engine lifecycle')
  assert_engine(Coverage.running?, 'finalization stopped Ruby Coverage')
ensure
  TestSift::Tracker::IOHooks.uninstall
end
