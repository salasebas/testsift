# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'open3'
require 'tmpdir'

RSpec.describe 'CurrentEvidence', if: RUBY_ENGINE == 'ruby' && RUBY_VERSION.start_with?('3.3.') &&
  RUBY_PLATFORM.match?(/linux|darwin/) do
  subject(:result) do
    _, status = Open3.capture2e(environment, RbConfig.ruby, '-r', bootstrap, '-e', script)
    payload = JSON.parse(File.read(Dir[File.join(root, 'telemetry.*.json')].fetch(0)))
    [status.exitstatus, payload.dig('metrics', 'work', 'calls'), payload.fetch('sampled_malloc_peak_bytes')]
  end

  let(:root) { Dir.mktmpdir('testsift-timing-spec') }
  let(:bootstrap) { File.expand_path('../../benchmark/evidence/timing_boot.rb', __dir__) }
  let(:script) { '3.times { Evidence.measure("work") { 1 + 1 } }' }
  let(:environment) do
    { 'EVIDENCE_TRACER' => '0', 'EVIDENCE_MODE' => 'plain', 'EVIDENCE_PROFILE' => '1',
      'EVIDENCE_TELEMETRY' => File.join(root, 'telemetry'), 'EVIDENCE_MALLOC_PROBE' => nil }
  end

  after { FileUtils.rm_rf(root) }

  it 'measures work without loading or sampling a native allocator probe' do
    expect(result).to eq([0, 3, nil])
  end
end
