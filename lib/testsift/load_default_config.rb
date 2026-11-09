# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
TestSift.configure do
  log_level :info
  fail_on_duplicates true

  filters.clear
  add_filter %w[
    /vendor/bundle/
    /lib/testsift/
    /lib/testsift.rb
    /usr/local/lib/ruby/
    /usr/local/bundle/
    /opt/hostedtoolcache/
    /.rbenv/versions/
    /.asdf/installs/ruby/
    /.rvm/
    /testsift_cache/
    /testsift_coverage/
    /testsift_report/
    testsift.lock
  ].freeze

  coverage_filters.clear
  add_coverage_filter %w[
    /autotest/
    /features/
    /spec/
    /test/
    /vendor/bundle/
    /lib/testsift/
    /lib/testsift.rb
    /usr/local/lib/ruby/
    /usr/local/bundle/
    /opt/hostedtoolcache/
    /.rbenv/versions/
    /.asdf/installs/ruby/
    /.rvm/
    /testsift_cache/
    /testsift_coverage/
    /testsift_report/
    testsift.lock
  ].freeze
end
# rubocop:enable Metrics/BlockLength
