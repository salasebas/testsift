# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'rbconfig'
require 'tmpdir'

# Loaded-file tracking reads the paths of the example-finish Coverage
# snapshot. These runs use real Coverage and real require/load/autoload
# to pin which example each newly loaded file is attributed to.
# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe RSpecTracer::Tracker::LoadedFilesTracker do
  let(:root) { Dir.mktmpdir('loaded-files') }
  let(:lib_path) { File.expand_path('../../lib', __dir__) }
  let(:first_run_files) { %w[/lib/boot_dep.rb /lib/setup_dep.rb /lib/body_dep.rb /lib/teardown_dep.rb] }

  before do
    File.write(File.join(root, '.rspec-tracer'), <<~RUBY)
      RSpecTracer.configure do
        run_all_examples false
        transitive_load_tracking true
        add_filter '/vendor/'
      end
    RUBY
    %w[boot setup body teardown context lazy loaded].each do |name|
      write("lib/#{name}_dep.rb", "module #{name.capitalize}Dep\n  VALUE = :#{name}\nend\n")
    end
    write('vendor/filtered_dep.rb', "module FilteredDep; end\n")
    write('loading_spec.rb', <<~RUBY)
      require 'rspec_tracer'
      RSpecTracer.start
      require_relative 'lib/boot_dep'
      autoload :LazyDep, File.join(__dir__, 'lib/lazy_dep.rb')

      RSpec.describe 'first group' do
        before { require_relative 'lib/setup_dep' }
        after { require_relative 'lib/teardown_dep' }

        it 'loads in its body' do
          require_relative 'lib/body_dep'
          require_relative 'vendor/filtered_dep'
          expect(BodyDep::VALUE).to eq(:body)
        end
      end

      RSpec.describe 'second group' do
        before(:context) { require_relative 'lib/context_dep' }

        it 'reads constants loaded earlier' do
          expect([SetupDep::VALUE, ContextDep::VALUE, LazyDep::VALUE]).to eq(%i[setup context lazy])
        end

        it 'loads a file and fails' do
          load File.join(__dir__, 'lib/loaded_dep.rb')
          expect(LoadedDep::VALUE).to eq(:different)
        end
      end
    RUBY
  end

  after { FileUtils.remove_entry(root) }

  def write(relative, contents)
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
  end

  def run_project
    Open3.capture2e(RbConfig.ruby, '-I', lib_path, '-rrspec/core', '-e', 'exit RSpec::Core::Runner.run(ARGV)',
                    File.join(root, 'loading_spec.rb'), chdir: root)
  end

  def cache(name)
    cache_root = File.join(root, 'rspec_tracer_cache')
    manifest = JSON.parse(File.read(File.join(cache_root, 'last_run.json')))
    JSON.parse(File.read(File.join(cache_root, manifest.fetch('run_id'), "#{name}.json")))
  end

  def dependencies_by_description
    examples = cache('all_examples')
    cache('dependency').to_h { |id, files| [examples.fetch(id).fetch('description'), files] }
  end

  it 'attributes files loaded in hooks, bodies, and between examples to the examples that observe them' do
    output, status = run_project
    expect(status.exitstatus).to eq(1), output

    dependencies = dependencies_by_description
    expect(dependencies.fetch('loads in its body')).to include(*first_run_files)
    expect(dependencies.fetch('loads in its body'))
      .not_to include('/lib/context_dep.rb', '/lib/lazy_dep.rb', '/lib/loaded_dep.rb')
    expect(dependencies.fetch('reads constants loaded earlier'))
      .to include(*first_run_files, '/lib/context_dep.rb', '/lib/lazy_dep.rb')
    expect(dependencies.fetch('reads constants loaded earlier')).not_to include('/lib/loaded_dep.rb')
    expect(dependencies.fetch('loads a file and fails')).to include('/lib/loaded_dep.rb')
    expect(dependencies.values.flatten).not_to include('/vendor/filtered_dep.rb')
    expect(cache('failed_examples').size).to eq(1)
  end

  it 'reselects only the examples that observed a file loaded between examples' do
    run_project
    write('lib/context_dep.rb', "module ContextDep\n  VALUE = :context\n  CHANGED = true\nend\n")

    output, status = run_project

    expect(status.exitstatus).to eq(1), output
    expect(output).to include('running 2 examples (actual: 3, skipped: 1)')
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
