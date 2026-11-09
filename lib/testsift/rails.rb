# frozen_string_literal: true

# Rails integration entry point. Loaded explicitly by users who put
# `require 'testsift/rails'` in their spec_helper - the gem does not
# auto-load this file, so pure-Ruby suites pay zero cost.
#
# Behavior:
#   - Always loads TestSift::Rails::Preset so Configuration#track_rails_defaults
#     works whether or not Rails itself is booted in the current process.
#   - Loads TestSift::Rails::Railtie iff `::Rails::Railtie` is defined,
#     so requiring this file when Rails is absent is a clean no-op
#     (AC1: "Rails absent: requiring testsift/rails noops cleanly").

require_relative 'rails/preset'
require_relative 'rails/railtie' if defined?(Rails::Railtie)
