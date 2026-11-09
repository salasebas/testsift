# frozen_string_literal: true

module TestSift
  module RSpec
    module RailsSetup
      def self.install(engine:, configuration:)
        ::RSpec.configure do |config|
          config.before(:suite) { RailsSetup.prepare(engine, configuration) }
        end
      rescue StandardError => e
        configuration.logger.warn(
          "testsift: Rails suite hook install failed (#{e.class}: #{e.message})"
        )
      end

      def self.prepare(engine, configuration)
        return unless defined?(::Rails::VERSION) && !::Rails::VERSION.nil?

        engine.install_rails_observers
        return unless engine.rails_observers_installed?
        return unless configuration.track_ar_schema_notifications?
        return unless ::RSpec.configuration.respond_to?(:use_transactional_fixtures)
        return if ::RSpec.configuration.use_transactional_fixtures == false

        configuration.logger.warn(
          'testsift: track_ar_schema_notifications is enabled but ' \
          'use_transactional_fixtures defaults to true; per-example ' \
          'BEGIN/COMMIT fires sql.active_record so db/schema.rb gets ' \
          'attributed to every AR-touching example (safe, but widens ' \
          'invalidation). For narrow attribution, set ' \
          'use_transactional_fixtures = false and use sequence-based ' \
          'factories (or another non-AR cleanup mechanism). See ' \
          'README section "Narrow AR-schema attribution".'
        )
      rescue StandardError => e
        configuration.logger.warn(
          "testsift: Rails suite setup failed (#{e.class}: #{e.message})"
        )
      end
    end
  end
end
