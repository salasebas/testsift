# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'

return unless RUBY_ENGINE == 'ruby'

begin
  require 'sqlite3'
rescue LoadError
  return
end

# A failing suite exits through `exit 1`, so the SQLite cache is read and
# written while that SystemExit is pending. sqlite3 1.x (the Ruby 3.1 pin)
# re-raises it from every statement, which aborted the second red run's
# finalize: no summary, and the cache stayed at the first run.
# rubocop:disable RSpec/DescribeClass, RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe 'SQLite cache persistence across failing runs' do
  let(:root) { Dir.mktmpdir('sqlite-red-run') }
  let(:lib_path) { File.expand_path('../../lib', __dir__) }

  before do
    File.write(File.join(root, '.testsift'), "TestSift.configure do\n  storage_backend :sqlite\nend\n")
    FileUtils.mkdir_p(File.join(root, 'lib'))
    File.write(File.join(root, 'lib/thing.rb'), "module Thing\n  VALUE = 1\nend\n")
    File.write(File.join(root, 'red_spec.rb'), <<~RUBY)
      require 'testsift'
      TestSift.start
      require_relative 'lib/thing'

      RSpec.describe 'red suite' do
        it('passes') { expect(Thing::VALUE).to eq(1) }
        it('fails') { expect(Thing::VALUE).to eq(2) }
      end
    RUBY
  end

  after { FileUtils.remove_entry(root) }

  def run_project
    Open3.capture2e(RbConfig.ruby, '-I', lib_path, '-rrspec/core', '-e', 'exit RSpec::Core::Runner.run(ARGV)',
                    File.join(root, 'red_spec.rb'), chdir: root)
  end

  it 'persists a reusable cache after a failing run and keeps the failing exit status' do
    first, first_status = run_project
    expect(first_status.exitstatus).to eq(1), first

    second, second_status = run_project

    expect(second_status.exitstatus).to eq(1), second
    expect(second).not_to include('not a valid SQLite database')
    expect(second).to include('running 1 examples (actual: 2, skipped: 1)')
    expect(second).to include('testsift: 2 examples tracked')
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/ExampleLength, RSpec/MultipleExpectations
