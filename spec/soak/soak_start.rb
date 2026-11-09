# frozen_string_literal: true

# Pre-loaded into the soak subprocess via RUBYOPT="-r<this-file>".
# Starts TestSift before the project's spec_helper / rails_helper
# runs, so Coverage interception sees the project's source files
# from the very first require.
#
# Universal hook: avoids having to patch each external project's
# spec_helper.rb / rails_helper.rb to insert TestSift.start at
# the right point. The soak fixture task only injects the gem into
# the project's Gemfile; this file does the runtime activation.
#
# Bundler.setup must run before requiring testsift because
# `bundle exec` appends `-rbundler/setup` to RUBYOPT *after* our
# `-r<this-file>`. At RUBYOPT processing time the bundle isn't yet
# activated and `require 'testsift'` would miss the gem path.
# Calling Bundler.setup explicitly here activates BUNDLE_GEMFILE's
# resolved gem set; the subsequent bundle/setup load (from bundler/
# setup added by bundle exec) is a no-op (Bundler.setup is
# idempotent).
#
# Graceful-degradation: if the require fails (fixture Gemfile didn't
# resolve testsift or Bundler.setup raises), warn to stderr and
# continue. The parent spec's verify_cache_state catches the
# missing-cache failure mode anyway - tracer-not-loaded surfaces
# there as "testsift_cache/ missing" rather than crashing this
# preload.

begin
  require 'bundler/setup'
  require 'testsift'
  TestSift.start
rescue LoadError, Bundler::BundlerError => e
  warn "soak_start: failed to start testsift (#{e.class}: #{e.message})"
end
