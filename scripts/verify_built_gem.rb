#!/usr/bin/env ruby
# frozen_string_literal: true

# Release check for a built testsift .gem. Installs the artifact into an
# empty GEM_HOME (no Bundler, no checkout on the load path) and runs the
# documented entry points from that install:
#
#   1. `require 'testsift'` resolves to the installed gem at the expected
#      version.
#   2. The `testsift` executable prints that version.
#   3. A copy of the Ruby benchmark fixture runs cold (all re-run, nothing skipped),
#      then warm (none re-run, all skipped from the cache the cold run wrote).
#
# Usage: ruby scripts/verify_built_gem.rb pkg/testsift-X.Y.Z.gem
# Run via: task release:verify
#
# Exits 0 when every check passes, 1 with the failing command's output
# otherwise.

require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'

ROOT = File.expand_path('..', __dir__)
FIXTURE = File.join(ROOT, 'benchmark/fixtures/ruby_app')
FIXTURE_FILES = %w[.rspec .testsift app spec].freeze
SUMMARY = /testsift: (?<tracked>\d+) examples tracked \S+ (?<rerun>\d+) re-run \S+ (?<skipped>\d+) skipped/

gem_file = File.expand_path(ARGV.fetch(0) { abort 'usage: ruby scripts/verify_built_gem.rb pkg/testsift-X.Y.Z.gem' })
version = File.basename(gem_file)[/\Atestsift-(.+)\.gem\z/, 1] || abort("not a testsift gem file: #{gem_file}")
abort "gem file not found: #{gem_file}" unless File.file?(gem_file)

def check(message)
  abort "FAIL: #{message}" unless yield

  puts "PASS: #{message}"
end

def run!(env, *cmd, chdir:)
  output, status = Open3.capture2e(env, *cmd, chdir: chdir)
  abort "FAIL: #{cmd.join(' ')} exited #{status.exitstatus}\n#{output}" unless status.success?

  output
end

# Runs an installed gem executable the way a RubyGems binstub does, so the
# check does not depend on the wrapper style of the local Ruby manager.
def run_executable!(env, gem_name, executable, *args, chdir:)
  run!(env, RbConfig.ruby, '-e', "load Gem.activate_bin_path(#{gem_name.dump}, #{executable.dump}, '>= 0')",
       '--', *args, chdir: chdir)
end

def summary_of(output)
  match = output.match(SUMMARY) || abort("FAIL: no testsift summary line in rspec output\n#{output}")
  match.named_captures.transform_values(&:to_i)
end

def isolated_env(gem_home)
  # The parent shell may run under `bundle exec` or a `task` that sets
  # TESTSIFT_* switches; the install under test must see none of them.
  inherited = ENV.keys.grep(/\A(BUNDLE_|BUNDLER_|RUBYOPT\z|RUBYLIB\z|GEM_|TESTSIFT_)/)
  inherited.to_h { |key| [key, nil] }.merge('GEM_HOME' => gem_home, 'GEM_PATH' => gem_home)
end

def verify_install(env, gem_home, version, chdir:)
  loaded = run!(env, RbConfig.ruby, '-e', <<~RUBY, chdir: chdir)
    require 'testsift'
    spec = Gem.loaded_specs.fetch('testsift')
    puts spec.version, spec.full_gem_path, TestSift::VERSION
  RUBY
  gem_version, gem_path, constant = loaded.lines.map(&:chomp)
  check("require 'testsift' loads #{version} from the isolated install (got #{gem_version} at #{gem_path})") do
    gem_version == version && constant == version && gem_path.start_with?(gem_home)
  end

  cli = run_executable!(env, 'testsift', 'testsift', '--version', chdir: chdir)
  check("`testsift --version` prints #{version}") { cli.strip == "testsift #{version}" }
end

def verify_fixture(env, app)
  FileUtils.mkdir_p(app)
  FIXTURE_FILES.each { |entry| FileUtils.cp_r(File.join(FIXTURE, entry), app) }

  # rspec-core falls back to `spec/` only when $0 is `rspec`; under
  # `ruby -e` the directory has to be named.
  cold = summary_of(run_executable!(env, 'rspec-core', 'rspec', 'spec', chdir: app))
  check("cold run re-runs all #{cold['tracked']} examples") do
    cold['tracked'].positive? && cold['rerun'] == cold['tracked'] && cold['skipped'].zero?
  end

  warm = summary_of(run_executable!(env, 'rspec-core', 'rspec', 'spec', chdir: app))
  check("warm run skips all #{warm['tracked']} unchanged examples and re-runs none") do
    warm['tracked'] == cold['tracked'] && warm['rerun'].zero? && warm['skipped'] == warm['tracked']
  end
end

Dir.mktmpdir('testsift-verify') do |dir|
  # macOS hands out /var/... temp paths that resolve to /private/var/...;
  # RubyGems reports the resolved form.
  tmp = File.realpath(dir)
  gem_home = File.join(tmp, 'gems')
  env = isolated_env(gem_home)

  run!(env, RbConfig.ruby, '-S', 'gem', 'install', gem_file, 'rspec:~> 3.13',
       '--no-document', '--install-dir', gem_home, chdir: tmp)
  verify_install(env, gem_home, version, chdir: tmp)
  verify_fixture(env, File.join(tmp, 'app'))
end
