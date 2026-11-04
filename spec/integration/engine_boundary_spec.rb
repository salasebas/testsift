# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe RSpecTracer::Engine do
  let(:root) { Dir.mktmpdir('engine-boundary') }
  let(:lib_path) { File.expand_path('../../lib', __dir__) }

  before do
    File.write(File.join(root, '.rspec-tracer'), <<~RUBY)
      RSpecTracer.configure do
        run_all_examples false
        transitive_load_tracking false
      end
    RUBY
    %w[setup body teardown around_tail].each do |name|
      File.write(File.join(root, "#{name}.yml"), "#{name}: true\n")
    end
    File.write(File.join(root, 'boundary_spec.rb'), <<~RUBY)
      require 'rspec_tracer'
      RSpecTracer.start

      RSpec.describe 'lifecycle' do
        around do |example|
          example.run
          File.read(File.join(__dir__, 'around_tail.yml'))
        end
        before { File.read(File.join(__dir__, 'setup.yml')) }
        after { File.read(File.join(__dir__, 'teardown.yml')) }

        it('reads body input', tracks: { env: 'ENGINE_BOUNDARY_FLAG' }) do
          File.read(File.join(__dir__, 'body.yml'))
          expect(ENV.fetch('ENGINE_BOUNDARY_FLAG')).to eq('enabled')
        end
      end
    RUBY
  end

  after { FileUtils.remove_entry(root) }

  def run_project(env = {})
    Open3.capture2e(
      { 'ENGINE_BOUNDARY_FLAG' => 'enabled' }.merge(env),
      RbConfig.ruby, '-I', lib_path, '-rrspec/core', '-e',
      'exit RSpec::Core::Runner.run(ARGV)', *Dir.glob(File.join(root, '*_spec.rb')).sort, chdir: root
    )
  end

  def cache(name)
    cache_root = File.join(root, 'rspec_tracer_cache')
    manifest = JSON.parse(File.read(File.join(cache_root, 'last_run.json')))
    JSON.parse(File.read(File.join(cache_root, manifest.fetch('run_id'), "#{name}.json")))
  end

  def report_examples
    report = JSON.parse(File.read(File.join(root, 'rspec_tracer_report', 'report.json')))
    report.fetch('reports').fetch('all_examples')
  end

  it 'records setup, body, teardown, and the around tail before skipping an unchanged run' do
    cold, cold_status = run_project
    expect(cold_status.exitstatus).to eq(0), cold
    expect(cache('dependency').values.flatten).to include(
      '/setup.yml', '/body.yml', '/teardown.yml', '/around_tail.yml'
    )
    expect(report_examples.first.fetch('execution_result').fetch('status')).to eq('passed')

    warm, warm_status = run_project
    expect(warm_status.exitstatus).to eq(0), warm
    expect(warm).to include('running 0 examples (actual: 1, skipped: 1)')
    expect(cache('dependency').values.flatten).to include('/around_tail.yml')
    expect(cache('all_examples').values.first.fetch('execution_result').fetch('status')).to eq('passed')
  end

  it 'selects a test when its teardown input changes' do
    run_project
    File.write(File.join(root, 'teardown.yml'), "teardown: changed\n")

    output, status = run_project

    expect(status.exitstatus).to eq(0), output
    expect(output).to include('running 1 examples (actual: 1, skipped: 0)')
    expect(report_examples.first.fetch('run_reason')).to eq('Files changed')
  end

  it 'retains ENV selection, failing exit status, and failed-history selection' do
    run_project
    failed, failed_status = run_project('ENGINE_BOUNDARY_FLAG' => 'disabled')
    expect(failed_status.exitstatus).to eq(1), failed
    expect(report_examples.first.fetch('run_reason')).to eq('Environment changed')
    expect(cache('failed_examples').size).to eq(1)

    repeated, repeated_status = run_project('ENGINE_BOUNDARY_FLAG' => 'disabled')
    expect(repeated_status.exitstatus).to eq(1), repeated
    expect(report_examples.first.fetch('run_reason')).to eq('Failed previously')
  end

  it 'selects a new identity from a warm cache and retains the previous result' do
    run_project
    old_id, old_metadata = cache('all_examples').first
    File.write(File.join(root, 'new_spec.rb'), <<~RUBY)
      RSpec.describe 'added identity' do
        it('is new') { expect(2 + 2).to eq(4) }
      end
    RUBY

    output, status = run_project

    expect(status.exitstatus).to eq(0), output
    expect(output).to include('running 1 examples (actual: 2, skipped: 1)')
    expect(report_examples.find { |example| example['description'] == 'added identity is new' })
      .to include('run_reason' => 'No cache', 'status' => 'passed')
    expect(cache('all_examples').fetch(old_id).fetch('execution_result')).to eq(old_metadata.fetch('execution_result'))

    warm, warm_status = run_project
    expect(warm_status.exitstatus).to eq(0), warm
    expect(warm).to include('running 0 examples (actual: 2, skipped: 2)')
  end

  it 'normalizes pending and explicit skip outcomes and selects them on the next run' do
    File.write(File.join(root, 'pending_spec.rb'), <<~RUBY)
      RSpec.describe 'deferred work' do
        it 'is pending' do
          pending 'not implemented'
          expect(false).to be(true)
        end
        xit('is skipped') { raise 'must not execute' }
      end
    RUBY
    cold, cold_status = run_project
    expect(cold_status.exitstatus).to eq(0), cold
    pending_ids = cache('pending_examples')
    expect(pending_ids.size).to eq(2)
    outcomes = cache('all_examples').values_at(*pending_ids).map { |example| example.fetch('execution_result') }
    expect(outcomes.map { |result| result.fetch('status') }).to eq(%w[pending pending])

    warm, warm_status = run_project

    expect(warm_status.exitstatus).to eq(0), warm
    expect(warm).to include('running 2 examples (actual: 3, skipped: 1)')
    expect(report_examples.select { |example| pending_ids.include?(example['id']) })
      .to all(include('run_reason' => 'Pending previously', 'status' => 'pending'))
  end

  it 'finalizes a graceful early exit and selects the interrupted test next time' do
    File.write(File.join(root, 'interrupted_spec.rb'), <<~RUBY)
      RSpec.describe 'interrupted work' do
        it 'completes after an interruption' do
          exit 9 if ENV['ENGINE_BOUNDARY_INTERRUPT'] == '1'
          expect(true).to be(true)
        end
      end
    RUBY
    interrupted, interrupted_status = run_project('ENGINE_BOUNDARY_INTERRUPT' => '1')
    expect(interrupted_status.exitstatus).to eq(9), interrupted
    interrupted_ids = cache('interrupted_examples')
    expect(interrupted_ids.size).to eq(1)

    resumed, resumed_status = run_project('ENGINE_BOUNDARY_INTERRUPT' => '0')

    expect(resumed_status.exitstatus).to eq(0), resumed
    expect(resumed).to include('running 1 examples (actual: 2, skipped: 1)')
    expect(report_examples.find { |example| example['id'] == interrupted_ids.first })
      .to include('run_reason' => 'Interrupted previously', 'status' => 'passed')
    expect(cache('interrupted_examples')).to be_empty
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
