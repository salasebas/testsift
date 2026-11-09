# frozen_string_literal: true

# End-to-end stdout purity of the `testsift` binary when the
# project's `.testsift` writes through the logger while it loads --
# BEFORE sub-command dispatch. The logger's default destination is
# stdout, so before the CLI rebound `Logger.default_out` around
# library boot such a line printed AHEAD of the `blast-radius --json`
# document and broke `... --json | jq`.
#
# Subprocess-driven because the failure mode lives at library load --
# it cannot be reproduced in-process once the spec suite has loaded
# testsift (a second `require 'testsift'` is a no-op, so the
# config-load window never reopens).

require 'json'
require 'open3'
require 'set'
require 'tmpdir'

require 'testsift/storage/json_backend'
require 'testsift/storage/snapshot'
require 'testsift/storage/schema'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'testsift binary with a project config that logs while loading' do
  def seed_cache(dir)
    snapshot = TestSift::Storage::Snapshot.empty(
      schema_version: TestSift::Storage::Schema::CURRENT, run_id: 'run_purity'
    )
    snapshot.all_examples = {
      'spec/calc_spec.rb[1:1]' => {
        'example_id' => 'spec/calc_spec.rb[1:1]',
        'full_description' => 'Calc adds',
        'rerun_file_name' => './spec/calc_spec.rb',
        'rerun_line_number' => 7
      }
    }
    snapshot.reverse_dependency = { '/lib/calc.rb' => Set.new(['spec/calc_spec.rb[1:1]']) }
    TestSift::Storage::JsonBackend.new(cache_path: File.join(dir, 'testsift_cache')).save_graph(
      snapshot, schema_version: TestSift::Storage::Schema::CURRENT
    )
  end

  def run_cli(config_body, *argv)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, '.testsift'), config_body)
      seed_cache(dir)
      Open3.capture3(
        {
          'BUNDLE_GEMFILE' => File.expand_path('../../Gemfile', __dir__),
          # Deleted (nil) so the subprocess cache_path stays exactly
          # <dir>/testsift_cache -- either var appends a scope
          # segment and would miss the seeded cache.
          'TEST_SUITE_ID' => nil,
          'TEST_ENV_NUMBER' => nil
        },
        'bundle', 'exec', 'ruby', File.expand_path('../../bin/testsift', __dir__), *argv,
        chdir: dir
      )
    end
  end

  it 'keeps `blast-radius --json` stdout strictly parseable with the config-load warning on stderr' do
    config = <<~CONFIG
      TestSift.configure do
        TestSift.logger.warn 'warning from .testsift'
      end
    CONFIG
    out, err, status = run_cli(config, 'blast-radius', '--json', 'lib/calc.rb')
    expect(status.exitstatus).to eq(0)
    # Strict parse over the WHOLE stdout capture is the contract
    # check: it raises if the warning line (or anything else)
    # precedes or follows the single JSON document.
    payload = JSON.parse(out)
    expect(payload['files'].first).to include('status' => 'tracked', 'example_count' => 1)
    expect(err).to include('warning from .testsift')
  end

  it 'keeps the stderr binding when the config resets log_level between logger writes' do
    # `Configuration#log_level` nils the memoized logger instance; the
    # next write constructs a fresh logger mid-load, which must still
    # pick up the CLI's stderr default.
    config = <<~CONFIG
      TestSift.configure do
        TestSift.logger.warn 'first warning'
        log_level :debug
        TestSift.logger.warn 'second warning'
      end
    CONFIG
    out, err, status = run_cli(config, 'blast-radius', '--json', 'lib/calc.rb')
    expect(status.exitstatus).to eq(0)
    expect { JSON.parse(out) }.not_to raise_error
    expect(err).to include('first warning')
    expect(err).to include('second warning')
  end
end
# rubocop:enable RSpec/DescribeClass
