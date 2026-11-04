# frozen_string_literal: true

require 'rspec_tracer/rspec/rails_setup'
require_relative '../support/engine_context'

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe RSpecTracer::RSpec::RailsSetup do
  include_context 'with engine configuration'

  def prepare_tracker(configuration_override = configuration)
    engine = RSpecTracer::Engine.new(configuration: configuration_override).setup
    described_class.install(engine: engine, configuration: configuration_override)
    engine
  end

  describe 'Rails late-bind when rails? is false at setup' do
    let(:captured_suite_blocks) { [] }
    let(:fake_rspec_config) do
      blocks = captured_suite_blocks
      cfg = Object.new
      cfg.define_singleton_method(:before) do |scope, &block|
        blocks << block if scope == :suite
      end
      cfg
    end

    let(:fake_as_notifications) do
      Class.new do
        def initialize
          @subscribers = {}
        end

        def subscribe(event_name, &block)
          handle = Object.new
          (@subscribers[event_name] ||= {})[handle] = block
          handle
        end

        def unsubscribe(handle)
          @subscribers.each_value { |blocks| blocks.delete(handle) }
        end

        attr_reader :subscribers
      end.new
    end

    before do
      allow(RSpec).to receive(:configure).and_yield(fake_rspec_config)
      stub_const('ActiveSupport', Module.new)
      stub_const('ActiveSupport::Notifications', fake_as_notifications)
    end

    after do
      if defined?(RSpecTracer::Rails::Notifications) && RSpecTracer::Rails::Notifications.installed?
        RSpecTracer::Rails::Notifications.uninstall
      end
      if defined?(RSpecTracer::Rails::I18nTracking) && RSpecTracer::Rails::I18nTracking.installed?
        RSpecTracer::Rails::I18nTracking.uninstall
      end
    end

    it 'registers a before(:suite) hook instead of installing eagerly' do
      prepare_tracker(stub_configuration(rails?: false))

      expect(captured_suite_blocks.size).to eq(1)
      expect(
        defined?(RSpecTracer::Rails::Notifications) &&
          RSpecTracer::Rails::Notifications.installed?
      ).to be_falsey
    end

    it 'installs Rails observers when the hook fires after Rails has loaded' do
      tracker = prepare_tracker(stub_configuration(rails?: false))
      hook = captured_suite_blocks.first

      stub_const('Rails', Module.new) unless defined?(Rails)
      stub_const('Rails::VERSION', Module.new)
      stub_const('Rails::VERSION::STRING', '7.2.3.1')

      hook.call

      expect(RSpecTracer::Rails::Notifications).to be_installed
      expect(tracker.send(:rails_observers_installed?)).to be(true)
    end

    it 'is a no-op when Rails still has not loaded by suite-start time' do
      prepare_tracker(stub_configuration(rails?: false))
      hook = captured_suite_blocks.first
      # Intentionally do NOT stub Rails::VERSION: the hook fires
      # before Rails was ever required (rare but possible in pure-Ruby
      # suites that opt into track_ar_schema_notifications by mistake).
      hide_const('Rails::VERSION') if defined?(Rails::VERSION)

      hook.call

      expect(
        defined?(RSpecTracer::Rails::Notifications) &&
          RSpecTracer::Rails::Notifications.installed?
      ).to be_falsey
    end

    it 'fires the AR-schema warn inline when track_ar_schema_notifications is enabled' do
      configuration = stub_configuration(rails?: false, track_ar_schema_notifications?: true)
      tracker = prepare_tracker(configuration)
      hook = captured_suite_blocks.first

      stub_const('Rails', Module.new) unless defined?(Rails)
      stub_const('Rails::VERSION', Module.new)
      stub_const('Rails::VERSION::STRING', '7.2.3.1')
      allow(RSpec.configuration).to receive_messages(respond_to?: true, use_transactional_fixtures: true)

      hook.call

      expect(logger).to have_received(:warn).with(
        a_string_including('track_ar_schema_notifications is enabled')
          .and(a_string_including('use_transactional_fixtures defaults to true'))
      )
      _ = tracker
    end

    it 'does not fire the AR-schema warn when use_transactional_fixtures is false' do
      configuration = stub_configuration(rails?: false, track_ar_schema_notifications?: true)
      prepare_tracker(configuration)
      hook = captured_suite_blocks.first

      stub_const('Rails', Module.new) unless defined?(Rails)
      stub_const('Rails::VERSION', Module.new)
      stub_const('Rails::VERSION::STRING', '7.2.3.1')
      allow(RSpec.configuration).to receive_messages(respond_to?: true, use_transactional_fixtures: false)

      hook.call

      expect(logger).not_to have_received(:warn).with(
        a_string_including('use_transactional_fixtures defaults to true')
      )
    end

    it 'is idempotent: re-firing the hook after a successful install does not double-install' do
      prepare_tracker(stub_configuration(rails?: false))
      hook = captured_suite_blocks.first

      stub_const('Rails', Module.new) unless defined?(Rails)
      stub_const('Rails::VERSION', Module.new)
      stub_const('Rails::VERSION::STRING', '7.2.3.1')

      hook.call
      installed_first = RSpecTracer::Rails::Notifications.installed?
      expect { hook.call }.not_to raise_error
      installed_second = RSpecTracer::Rails::Notifications.installed?

      expect([installed_first, installed_second]).to eq([true, true])
    end

    it 'rescues StandardError raised by RSpec.configure during the late-bind install' do
      allow(RSpec).to receive(:configure).and_raise(StandardError, 'rspec wedge')

      expect { prepare_tracker(stub_configuration(rails?: false)) }.not_to raise_error
      expect(logger).to have_received(:warn).with(a_string_including('Rails suite hook install failed'))
    end
  end

  describe 'arm_ar_schema_setup_warn (eager path) hook body + rescue' do
    let(:captured_suite_blocks) { [] }
    let(:fake_rspec_config) do
      blocks = captured_suite_blocks
      cfg = Object.new
      cfg.define_singleton_method(:before) do |scope, &block|
        blocks << block if scope == :suite
      end
      cfg
    end

    let(:fake_as_notifications) do
      Class.new do
        def initialize
          @subscribers = {}
        end

        def subscribe(event_name, &block)
          handle = Object.new
          (@subscribers[event_name] ||= {})[handle] = block
          handle
        end

        def unsubscribe(handle)
          @subscribers.each_value { |blocks| blocks.delete(handle) }
        end
      end.new
    end

    before do
      stub_const('ActiveSupport', Module.new)
      stub_const('ActiveSupport::Notifications', fake_as_notifications)
      stub_const('Rails', Module.new) unless defined?(Rails)
      stub_const('Rails::VERSION', Module.new)
      stub_const('Rails::VERSION::STRING', '7.2.3.1')
    end

    after do
      if defined?(RSpecTracer::Rails::Notifications) && RSpecTracer::Rails::Notifications.installed?
        RSpecTracer::Rails::Notifications.uninstall
      end
      if defined?(RSpecTracer::Rails::I18nTracking) && RSpecTracer::Rails::I18nTracking.installed?
        RSpecTracer::Rails::I18nTracking.uninstall
      end
    end

    it 'fires emit_ar_schema_setup_warn_if_needed when the registered hook runs' do
      allow(RSpec).to receive(:configure).and_yield(fake_rspec_config)
      configuration = stub_configuration(rails?: true, track_ar_schema_notifications?: true)
      prepare_tracker(configuration)
      hook = captured_suite_blocks.first
      allow(RSpec.configuration).to receive_messages(respond_to?: true, use_transactional_fixtures: true)

      hook.call

      expect(logger).to have_received(:warn).with(
        a_string_including('use_transactional_fixtures defaults to true')
      )
    end

    it 'rescues StandardError raised by RSpec.configure during the warn install' do
      allow(RSpec).to receive(:configure).and_raise(StandardError, 'rspec wedge')
      configuration = stub_configuration(rails?: true, track_ar_schema_notifications?: true)

      expect { prepare_tracker(configuration) }.not_to raise_error
      expect(logger).to have_received(:warn).with(a_string_including('Rails suite hook install failed'))
    end

    it 'does not emit schema advice when observers could not be installed' do
      config = stub_configuration(rails?: false, track_ar_schema_notifications?: true)
      engine = build_tracker(config).tap(&:setup)
      allow(engine).to receive(:install_rails_observers)

      described_class.prepare(engine, config)

      expect(logger).not_to have_received(:warn)
    end

    it 'supports Rails without the rspec-rails transactional-fixture setting' do
      config = stub_configuration(rails?: true, track_ar_schema_notifications?: true)
      engine = build_tracker(config).tap(&:setup)
      allow(RSpec.configuration).to receive(:respond_to?).with(:use_transactional_fixtures).and_return(false)

      described_class.prepare(engine, config)

      expect(logger).not_to have_received(:warn)
    end

    it 'contains tracer failures raised while the suite callback runs' do
      config = stub_configuration(rails?: false)
      engine = build_tracker(config).tap(&:setup)
      allow(engine).to receive(:install_rails_observers).and_raise(StandardError, 'observer unavailable')

      described_class.prepare(engine, config)

      expect(logger).to have_received(:warn).with(a_string_including('Rails suite setup failed'))
    end
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
