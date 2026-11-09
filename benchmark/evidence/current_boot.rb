# frozen_string_literal: true

require 'fiddle'
require_relative 'boot'
require_relative 'host'

module CurrentEvidence
  def self.profile_targets
    {
      RSpecTracer::Engine => {
        seed_graph_from_previous: 'graph_restore', graph_from_previous: 'graph_restore',
        register_example: 'example_registration'
      },
      RSpecTracer::Tracker::DependencyGraph => { build_inverse_index: 'graph_index' },
      RSpecTracer::Tracker::IOHooks.singleton_class => { record: 'io_hooks', record_ruby_load: 'io_hooks' },
      RSpecTracer::Storage::JsonBackend => { decode_field: 'cache_model' },
      RSpecTracer::Storage::SqliteBackend => {
        load_graph: 'cache_load', save_graph: 'cache_save', read_field: 'cache_decode', dispatch_read: 'cache_model'
      },
      RSpecTracer::Storage::Serializer::Msgpack.singleton_class => {
        encode: 'cache_codec_encode', decode: 'cache_codec_decode'
      },
      RSpecTracer::RSpec::ParallelTests.singleton_class => {
        wait_for_peer_done_markers!: 'worker_wait', emit_merged_reporters!: 'reports'
      }
    }
  end

  def self.install_profile
    profile_targets.each do |target, methods|
      methods.each do |method, label|
        raise "profile target missing: #{target}##{method}" unless target.method_defined?(method) ||
          target.private_method_defined?(method)

        Evidence.wrap(target, method, label)
      end
    end
    profile_interning
    return unless defined?(::ParallelTests)

    Evidence.wrap(::ParallelTests.singleton_class, :wait_for_other_processes_to_finish, 'worker_wait')
  end

  def self.profile_interning
    RSpecTracer::Storage::JsonBackend.prepend(Module.new do
      def deep_intern(object)
        return super if @intern_profile_active

        @intern_profile_active = true
        begin
          Evidence.measure('cache_intern') { super }
        ensure
          @intern_profile_active = false
        end
      end

      private :deep_intern
    end)
  end

  def self.memory
    { process_peak_rss_kib: PerformanceEvidence::Host.process_peak_rss_kib,
      gc_malloc_increase_bytes: GC.stat(:malloc_increase_bytes),
      gc_oldmalloc_increase_bytes: GC.stat(:oldmalloc_increase_bytes),
      sampled_malloc_peak_bytes: @malloc_peak,
      native_allocator_note: 'Allocator used bytes (glibc mallinfo2 or macOS malloc zones) include Ruby heap ' \
                             'arenas; profile boundary samples are lower bounds.' }
  end

  def self.sample_malloc
    @malloc_handle ||= Fiddle.dlopen(ENV.fetch('EVIDENCE_MALLOC_PROBE'))
    @malloc ||= Fiddle::Function.new(@malloc_handle['evidence_malloc_bytes'],
                                     [], Fiddle::TYPE_SIZE_T)
    @malloc_peak = [@malloc_peak || 0, @malloc.call].max
  end

  def self.finish
    Evidence.original_finish
    path = "#{ENV.fetch('EVIDENCE_TELEMETRY')}.#{Process.pid}.json"
    payload = JSON.parse(File.read(path))
    payload.merge!(memory)
    payload[:jit] = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
    if ENV['EVIDENCE_TRACER'] == '1'
      backend = RSpecTracer.engine.storage_backend
      payload[:storage_class] = backend.class.name
      payload[:serializer] = backend.serializer_name if backend.respond_to?(:serializer_name)
    end
    File.write(path, JSON.generate(payload))
  end
end

Evidence.singleton_class.class_eval do
  alias_method :original_finish, :finish
  alias_method :original_measure, :measure

  def finish
    CurrentEvidence.finish
  end

  def measure(label, &block)
    original_measure(label, &block)
  ensure
    CurrentEvidence.sample_malloc unless @finished
  end
end

if ENV['EVIDENCE_PROFILE'] == '1'
  CurrentEvidence.install_profile if ENV['EVIDENCE_TRACER'] == '1'
  Evidence.wrap(RSpec::Core::Configuration, :load_spec_files, 'discovery')
  Evidence.wrap(RSpec::Core::Runner, :setup, 'runner_setup')
end
