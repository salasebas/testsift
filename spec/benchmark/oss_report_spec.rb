# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'
require_relative '../../benchmark/oss/report'

RSpec.describe OSSBenchmark::Report do
  let(:directory) do
    Dir.mktmpdir('testsift-oss-report').tap do |path|
      File.write(File.join(path, 'examples.json'), '[["a","passed"]]')
    end
  end
  let(:row) do
    { artifact_directory: directory, project: 'p', suite: 'smoke', case: 'fault', tracer: 'testsift',
      variant: 'fault', round: 0, valid: true,
      wall_seconds: 1.0, executed: 1, total: 4, selected_ratio: 0.25, errors: [], missed_failures: %w[c],
      status_mismatches: [] }
  end

  after { FileUtils.rm_rf(directory) }

  it 'marks a campaign with a missed failure as invalid while keeping the sample' do
    summary = described_class.summarize([row], {}, [])
    expect(summary).to include(valid: false, cells: [include(missed_failures: 1, valid_samples: 1)])
  end

  it 'keeps preflight, oracle, and prime rows out of the measured cells' do
    expect(described_class.summarize([row.merge(round: 'prime', missed_failures: [])], {}, [])).to include(
      valid: true, cells: []
    )
  end

  it 'uses nearest-rank percentiles' do
    expect([described_class.percentile([5, 1, 4, 2, 3], 0.5),
            described_class.percentile([5, 1, 4, 2, 3], 0.95)]).to eq([3, 5])
  end
end
