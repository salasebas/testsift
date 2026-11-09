# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'
require 'testsift/tracker/io_hooks'
require 'testsift/tracker/io_hooks/json'

RSpec.describe TestSift::Tracker::IOHooks::JSONReads do
  let(:tmp_base) { Dir.mktmpdir }
  let(:root) { File.join(tmp_base, 'project').tap { |p| FileUtils.mkdir_p(p) } }
  let(:bucket) { {} }
  let(:fixture) do
    path = File.join(root, 'config.json')
    File.write(path, '{"a":1}')
    path
  end

  after { FileUtils.rm_rf(tmp_base) if tmp_base }

  around do |example|
    TestSift::Tracker::IOHooks.install(root: root)
    example.run
  ensure
    TestSift::Tracker::IOHooks.uninstall
  end

  describe '#load_file' do
    let(:parsed) do
      TestSift::Tracker::IOHooks.with_bucket(bucket) { JSON.load_file(fixture) }
    end

    it 'records the path' do
      parsed
      expect(bucket).to have_key('data:config.json')
    end

    it 'returns the parsed JSON via super' do
      expect(parsed).to eq('a' => 1)
    end

    it 'forwards to super without recording when no bucket is active' do
      TestSift::Tracker::IOHooks.clear_bucket

      expect(JSON.load_file(fixture)).to eq('a' => 1)
    end
  end
end
