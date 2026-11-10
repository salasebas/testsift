# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'set'
require 'tmpdir'
require_relative '../../benchmark/oss/validation'
require_relative '../../benchmark/oss/report'

RSpec.describe OSSBenchmark::Validation do
  let(:directory) { Dir.mktmpdir('testsift-oss-validation') }
  let(:oracle_ids) { %w[a b c d] }
  let(:oracle) { { ids: oracle_ids.to_set, failures: [], total: oracle_ids.size } }
  let(:expected) { { source: 'rubygems', version: '0.0.1' } }
  let(:process) do
    { 'pid' => 1, 'finished' => true, 'tracer_started' => true, 'tracer_version' => '0.0.1',
      'tracer_path' => '/gems/testsift-0.0.1' }
  end

  after { FileUtils.rm_rf(directory) }

  def row(examples, processes: [process], exit_code: 0, cache_examples: 4, duplicate_examples: 0)
    File.write(File.join(directory, 'examples.json'), JSON.generate(examples))
    { artifact_directory: directory, processes: processes, executed: examples.size,
      unique_executed: examples.map(&:first).uniq.size, exit_code: exit_code,
      failures: examples.select { |_, status| status == 'failed' }.map(&:first),
      cache_examples: cache_examples, duplicate_examples: duplicate_examples }
  end

  def validate(data, kase: 'full', processes: 1, with_oracle: oracle)
    data[:case] = kase
    data[:tracer] = 'testsift'
    described_class.new(data, with_oracle, processes: processes, tracer_version: expected).apply
    data
  end

  def passed(*ids)
    ids.map { |id| [id, 'passed'] }
  end

  it 'accepts a complete traced full run' do
    expect(validate(row(passed('a', 'b', 'c', 'd')))).to include(valid: true, selected_ratio: 1.0, errors: [])
  end

  it 'rejects a run whose worker never reported' do
    data = validate(row(passed('a', 'b', 'c', 'd')), processes: 2)
    expect(data[:errors]).to include('1 RSpec processes reported, expected 2')
  end

  it 'rejects a worker that did not reach its exit hook' do
    data = validate(row(passed('a', 'b', 'c', 'd'), processes: [process.merge('finished' => nil)]))
    expect(data[:errors]).to include('an RSpec process did not finish')
  end

  it 'rejects an example executed by two workers' do
    data = validate(row(passed('a', 'b', 'c', 'd', 'a'), cache_examples: 4))
    expect(data[:errors]).to include('an example ran in more than one process')
  end

  it 'rejects a traced run whose tracer did not start or loaded another version' do
    broken = process.merge('tracer_started' => nil, 'tracer_version' => '2.0.0.rc.1')
    data = validate(row(passed('a', 'b', 'c', 'd'), processes: [broken]))
    expect(data[:errors]).to include('testsift did not start in pid 1',
                                     'testsift loaded 2.0.0.rc.1 from /gems/testsift-0.0.1')
  end

  it 'rejects a run during which the host slept' do
    data = validate(row(passed('a', 'b', 'c', 'd')).merge(slept_seconds: 8634.2))
    expect(data[:errors]).to include('host slept 8634.2 s during the run')
  end

  it 'rejects a nonzero exit without failing examples' do
    data = validate(row(passed('a', 'b', 'c', 'd'), exit_code: 1))
    expect(data[:errors]).to include('exit 1 with 0 failing examples')
  end

  it 'rejects a full run that skipped examples the tracer did not report as duplicates' do
    data = validate(row(passed('a', 'b', 'c'), cache_examples: 4))
    expect(data[:errors]).to include('1 oracle examples did not run (tracer reported 0 duplicates)')
  end

  it 'accounts for examples the tracer reports as duplicate identities' do
    data = validate(row(passed('a', 'b'), cache_examples: 2, duplicate_examples: 2))
    expect(data).to include(valid: true, unexecuted: 2)
  end

  it 'rejects an incomplete persisted cache' do
    data = validate(row(passed('a', 'b', 'c', 'd'), cache_examples: 1))
    expect(data[:errors]).to include('cache holds 1 examples, expected at least 4')
  end

  it 'accepts a cache that still holds identities a change removed' do
    expect(validate(row(passed('a', 'b', 'c', 'd'),
                        cache_examples: 6))).to include(valid: true, stale_cache_examples: 2)
  end

  it 'rejects examples the plain oracle never discovered' do
    data = validate(row(passed('a', 'b', 'c', 'd', 'z'), cache_examples: 4))
    expect(data[:errors]).to include('1 examples are absent from the plain oracle')
  end

  it 'records a failure that the oracle saw but the selection omitted' do
    failing = { ids: oracle_ids.to_set, failures: %w[c], total: 4 }
    data = validate(row(passed('a')), kase: 'fault', with_oracle: failing)
    expect(data).to include(valid: true, missed_failures: %w[c])
  end

  it 'records a selected example whose status differs from the oracle' do
    failing = { ids: oracle_ids.to_set, failures: %w[c], total: 4 }
    data = validate(row([%w[c passed]]), kase: 'fault', with_oracle: failing)
    expect(data[:status_mismatches]).to eq(%w[c])
  end
end
