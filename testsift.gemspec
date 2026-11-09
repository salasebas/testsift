# frozen_string_literal: true

$LOAD_PATH.push File.expand_path('lib', __dir__)

require 'testsift/version'

Gem::Specification.new do |spec|
  spec.name = 'testsift'
  spec.version = TestSift::VERSION
  spec.authors = ['Sebastian Sala', 'Abhimanyu Singh']

  spec.homepage = 'https://github.com/salasebas/testsift'
  spec.summary = <<-SUMMARY.strip.gsub(/\s+/, ' ')
    Affected-test selection for RSpec: re-run only the examples whose
    recorded inputs changed, with flaky-test detection and a per-example
    dependency map.
  SUMMARY
  spec.description = <<-DESCRIPTION.strip.gsub(/\s+/, ' ')
    TestSift records the inputs each RSpec example consumes -- using
    Ruby's built-in coverage library plus explicit declarations -- and turns
    that record into a flaky-test detector, a per-example dependency map, and
    optional CI acceleration that skips the examples whose recorded inputs
    are unchanged. It never skips failed, flaky, or pending examples.
  DESCRIPTION
  spec.license = 'MIT'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = "https://github.com/salasebas/testsift/tree/v#{spec.version}"
  spec.metadata['changelog_uri'] = "https://github.com/salasebas/testsift/blob/v#{spec.version}/CHANGELOG.md"
  spec.metadata['bug_tracker_uri'] = 'https://github.com/salasebas/testsift/issues'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.required_ruby_version = '>= 3.1.0'

  spec.add_dependency 'docile', '~> 1.4'
  spec.add_dependency 'rspec-core', '~> 3.12'

  spec.files = `git ls-files -- lib/*`.chomp.split("\n")
  spec.files += %w[CHANGELOG.md README.md LICENSE]
  spec.bindir = 'bin'
  spec.executables = ['testsift']
  spec.require_paths = ['lib']
end
