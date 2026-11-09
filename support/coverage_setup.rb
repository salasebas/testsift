# frozen_string_literal: true

def setup_simplecov
  return unless ENV.fetch('SKIP_COVERAGE_VALIDATION', 'false') == 'true'

  require 'simplecov'

  SimpleCov.command_name "#{ENV.fetch('SIMPLECOV_COMMAND_NAME', nil)}:#{Process.pid}"
  SimpleCov.root File.expand_path('..', __dir__)

  SimpleCov.start do
    enable_coverage :branch if ENV.fetch('BRANCH_COVERAGE', 'false') == 'true'

    add_filter %w[/features/ /spec/ /tmp/]
  end
end

def setup_testsift
  return unless ENV.fetch('SKIP_COVERAGE_VALIDATION', 'false') == 'true'

  require File.join(File.expand_path('..', __dir__), 'lib', 'testsift')

  # The DSL wrappers are installed by `Configuration#configure` during
  # `load_default_config` (auto-triggered by the `require` above). No
  # second install needed here.

  TestSift.add_filter %w[
    /.rbenv/versions/ /.asdf/installs/ruby/ /.rubies/ruby-head/
    /.rvm/gems/ /.rvm/rubies/ /bundler/gems/ /opt/hostedtoolcache/
    /testsift/ /ruby/gems/ /vendor/bundle/
  ]

  TestSift.add_coverage_filter %w[
    /.rbenv/versions/ /.asdf/installs/ruby/ /.rubies/ruby-head/
    /.rvm/gems/ /.rvm/rubies/ /bundler/gems/ /autotest/
    /features/ /opt/hostedtoolcache/ /ruby/gems/ /spec/ /test/ /vendor/bundle/
  ]
end

if ENV.fetch('SKIP_COVERAGE_VALIDATION', 'false') == 'true' && File.file?('Gemfile.lock')
  setup_simplecov
  setup_testsift

  module TestSiftCoverageReporter
    def peek_coverage
      data = ::Coverage.peek_result

      return data if data.first.last.is_a?(Array)

      data.transform_values { |stats| stats[:lines] }
    end
  end

  main_clazz = TestSift::CoverageReporter
  clazz = TestSiftCoverageReporter

  main_clazz.prepend(clazz) unless main_clazz.ancestors.include?(clazz)
end
