# frozen_string_literal: true

require 'testsift/engine'
require_relative 'support/engine_context'

# rubocop:disable RSpec/ExampleLength
RSpec.describe TestSift::Engine do
  include_context 'with engine configuration'

  describe 'Rails observer wiring' do
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

        def publish(event_name, payload)
          (@subscribers[event_name] || {}).each_value do |b|
            b.call(event_name, Time.now, Time.now, 'id', payload)
          end
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
      if defined?(TestSift::Rails::Notifications) && TestSift::Rails::Notifications.installed?
        TestSift::Rails::Notifications.uninstall
      end
      if defined?(TestSift::Rails::I18nTracking) && TestSift::Rails::I18nTracking.installed?
        TestSift::Rails::I18nTracking.uninstall
      end
    end

    it 'installs the Rails notification observers when rails? is true' do
      tracker = build_tracker(stub_configuration(rails?: true)).tap(&:setup)

      expect(TestSift::Rails::Notifications).to be_installed
    ensure
      tracker&.finalize
    end

    it 'skips observer install when rails? is false' do
      build_tracker.tap(&:setup)

      expect(defined?(TestSift::Rails::Notifications) &&
        TestSift::Rails::Notifications.installed?).to be_falsey
    end

    it 'routes notification bucket through example_started / example_finished' do
      tracker = build_tracker(stub_configuration(rails?: true)).tap(&:setup)
      stub_example_snapshots(tracker, {}, {})
      template = File.join(root, 'app/views/show.erb')
      FileUtils.mkdir_p(File.dirname(template))
      File.write(template, '<h1>x</h1>')

      tracker.register_example(build_example('ex1'))
      tracker.example_started
      fake_as_notifications.publish('render_template.action_view', { identifier: template })
      tracker.example_finished('ex1')

      expect(tracker.graph.paths_for('ex1')).to include(template)
    ensure
      tracker&.finalize
    end

    it 'uninstalls Rails observers during finalize' do
      tracker = build_tracker(stub_configuration(rails?: true)).tap(&:setup)

      tracker.finalize

      expect(TestSift::Rails::Notifications).not_to be_installed
    end

    it 'installs the AR subscriber when track_ar_schema_notifications is true' do
      FileUtils.mkdir_p(File.join(root, 'db'))
      File.write(File.join(root, 'db/schema.rb'), "ActiveRecord::Schema.define { }\n")

      build_tracker(stub_configuration(rails?: true, track_ar_schema_notifications?: true))
        .tap(&:setup)

      expect(fake_as_notifications.instance_variable_get(:@subscribers).keys)
        .to include('sql.active_record')
    end

    it 'swallows errors raised during Rails observer install' do
      allow(TestSift::Rails::Notifications).to receive(:install)
        .and_raise(StandardError.new('boom'))

      expect do
        build_tracker(stub_configuration(rails?: true)).tap(&:setup)
      end.not_to raise_error
    end
  end
end
# rubocop:enable RSpec/ExampleLength
