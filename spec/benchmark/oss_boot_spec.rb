# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'open3'
require 'tmpdir'
require_relative '../../benchmark/oss/boot'

RSpec.describe OSSBenchmark::Boot, if: RUBY_ENGINE == 'ruby' && RUBY_PLATFORM.match?(/linux|darwin/) do
  let(:root) { Dir.mktmpdir('testsift-oss-boot') }
  let(:results) { File.join(root, 'results') }
  let(:boot) { File.expand_path('../../benchmark/oss/boot.rb', __dir__) }

  before do
    FileUtils.mkdir_p(results)
    File.write(File.join(root, 'sample_spec.rb'), <<~RUBY)
      RSpec.describe 'sample' do
        it('passes') { expect(1).to eq(1) }
        it('fails') { expect(1).to eq(2) }
        it('forks') { Process.wait(fork { nil }) }
        it('is filtered', :skip_me) { raise 'never runs' }
      end
    RUBY
  end

  after { FileUtils.rm_rf(root) }

  def telemetry(tracer)
    env = { 'RUBYOPT' => "-r#{boot}", 'OSS_RESULTS' => results, 'OSS_TRACER' => tracer,
            'BUNDLE_GEMFILE' => File.expand_path('../../Gemfile', __dir__), 'TESTSIFT_DISABLE' => nil }
    Open3.capture2e(env, 'bundle', 'exec', 'rspec', '--tag', '~skip_me', 'sample_spec.rb', chdir: root)
    files = Dir[File.join(results, 'process.*.json')]
    raise "expected one telemetry file, got #{files.size}" unless files.one?

    JSON.parse(File.read(files.first))
  end

  it 'records only the examples RSpec executed, with their statuses and exit status' do
    expect(telemetry(nil)).to include('finished' => true, 'exit_status' => 1, 'tracer' => nil,
                                      'examples' => contain_exactly([anything, 'passed'], [anything, 'passed'],
                                                                    [anything, 'failed']))
  end

  it 'starts the requested tracer before the suite loads' do
    expect(telemetry('testsift')).to include('tracer_started' => true, 'tracer_version' => TestSift::VERSION,
                                             'examples' => have_attributes(size: 3))
  end
end
