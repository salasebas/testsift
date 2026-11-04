# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'
require_relative '../../benchmark/evidence/corpus'

RSpec.describe PerformanceEvidence::Corpus, unless: RUBY_ENGINE == 'jruby' do
  subject(:result) do
    described_class.new(files: 2, branch_sites: 3, examples: 24, fanout: 1, inputs: 2, eager: false).write(root)
    output, status = Open3.capture2(RbConfig.ruby, '-e', script, root)
    [status.exitstatus, JSON.parse(output)]
  end

  let(:root) { Dir.mktmpdir('testsift-corpus-spec') }
  let(:script) do
    <<~RUBY
      require 'coverage'
      require 'json'
      Coverage.start(lines: true, branches: true)
      Dir[File.join(ARGV[0], 'app/*.rb')].sort.each { |path| load path }
      results = [ScaleWork0, ScaleWork1].flat_map { |work| [work.call(1), work.call(-1)] }
      snapshot = Coverage.peek_result
      puts JSON.generate(files: snapshot.size, branches: snapshot.values.sum { |entry| entry[:branches].size },
                         results: results)
    RUBY
  end

  after { FileUtils.rm_rf(root) }

  it 'generates executable files with real Coverage branches and known results' do
    expect(result).to eq([0, { 'files' => 2, 'branches' => 6, 'results' => [3, 0, 3, 0] }])
  end
end
