# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'tmpdir'
require 'yaml'

require 'testsift/rails/preset'
require 'testsift/tracker/declared_globs'
require 'testsift/tracker/io_hooks'

# Regression spec for the YAML-fixture blind-spot.
# Rails fixtures (spec/fixtures/**/*.{yml,yaml}) are loaded via
# ActiveRecord::FixtureSet, which funnels through YAML.load_file. The
# IOHooks YAML hook catches every read, so the fixture file gets
# attributed as a :data Input on every example that loads it. In
# parallel, Preset's `:fixtures` glob declared-walks the same files at
# boot for a conservative suite-wide fallback.
#
# This spec does not introduce a new lib file - it asserts both
# pipes see a fixture change after mutation, so the regression
# path is mechanically verifiable end-to-end.
# rubocop:disable RSpec/DescribeClass, RSpec/ExampleLength
RSpec.describe 'Fixture tracking regression' do
  let(:tmpdir) { Dir.mktmpdir('testsift-fixture') }
  let(:fixture_path) { File.join(tmpdir, 'spec/fixtures/users.yml') }

  before do
    FileUtils.mkdir_p(File.dirname(fixture_path))
    File.write(fixture_path, <<~YAML)
      alice:
        email: alice@example.com
      bob:
        email: bob@example.com
    YAML
  end

  after do
    TestSift::Tracker::IOHooks.uninstall if TestSift::Tracker::IOHooks.installed?
    TestSift::Tracker::IOHooks.clear_bucket
    FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir)
  end

  describe 'via DeclaredGlobs + Preset :fixtures' do
    it 'enumerates the fixture file with kind :declared' do
      globs = TestSift::Rails::Preset::DEFAULTS[:fixtures]
      declared = TestSift::Tracker::DeclaredGlobs.new(root: tmpdir, globs: globs)

      inputs = declared.walk

      expect(inputs.map(&:path)).to include(File.expand_path(fixture_path))
    end

    it 'emits a digest that flips when the fixture contents change' do
      globs = TestSift::Rails::Preset::DEFAULTS[:fixtures]
      declared_before = TestSift::Tracker::DeclaredGlobs.new(root: tmpdir, globs: globs)
      input_before = declared_before.walk.find { |i| i.path == File.expand_path(fixture_path) }

      File.write(fixture_path, "alice:\n  email: alice+new@example.com\n")
      declared_after = TestSift::Tracker::DeclaredGlobs.new(root: tmpdir, globs: globs)
      input_after = declared_after.walk.find { |i| i.path == File.expand_path(fixture_path) }

      expect(input_after.digest).not_to eq(input_before.digest)
    end
  end

  describe 'via IOHooks YAML.load_file interception' do
    it 'records the fixture path as a :data Input when YAML.load_file runs' do
      TestSift::Tracker::IOHooks.install(root: tmpdir, filter: ->(_p) { true })
      bucket = {}
      TestSift::Tracker::IOHooks.set_bucket(bucket)

      YAML.load_file(fixture_path)

      input = bucket.values.find { |i| i.path == File.expand_path(fixture_path) }
      expect(input.kind).to eq(:data)
    end

    it 'produces a digest that flips after a fixture mutation' do
      TestSift::Tracker::IOHooks.install(root: tmpdir, filter: ->(_p) { true })
      bucket_before = {}
      TestSift::Tracker::IOHooks.set_bucket(bucket_before)
      YAML.load_file(fixture_path)
      digest_before = bucket_before.values.find { |i| i.path == File.expand_path(fixture_path) }.digest
      TestSift::Tracker::IOHooks.clear_bucket

      File.write(fixture_path, "alice:\n  email: alice+v2@example.com\n")
      bucket_after = {}
      TestSift::Tracker::IOHooks.set_bucket(bucket_after)
      YAML.load_file(fixture_path)
      digest_after = bucket_after.values.find { |i| i.path == File.expand_path(fixture_path) }.digest

      expect(digest_after).not_to eq(digest_before)
    end

    it 'skips attribution when a declared glob already covers the path (IOHooks filter)' do
      declared = TestSift::Tracker::DeclaredGlobs.new(
        root: tmpdir, globs: TestSift::Rails::Preset::DEFAULTS[:fixtures]
      )
      TestSift::Tracker::IOHooks.install(
        root: tmpdir, filter: ->(path) { !declared.covers?(path) }
      )
      bucket = {}
      TestSift::Tracker::IOHooks.set_bucket(bucket)

      YAML.load_file(fixture_path)

      expect(bucket).to be_empty
    end
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/ExampleLength
