# frozen_string_literal: true

# Loading the preset defines `TestSift::Rails`, the module the
# Railtie class lives inside. Railtie.rb itself expects
# `::Rails::Railtie` to already be defined; the before-block below
# stubs that base class so this spec can run without the real Rails
# gem in the object graph.
require 'testsift/rails/preset'

# Top-level string-form describe (rather than `describe TestSift::Rails::Railtie`)
# because the constant only comes into existence inside the before-block (after
# Rails::Railtie is stubbed and railtie.rb is loaded) - a class-form describe
# would NameError at file-load time. Mutant's first-token test-to-subject
# mapping then credits these tests to `TestSift::Rails::Railtie`, matching
# the subject scoped by `task test:mutation:rails`.
RSpec.describe 'TestSift::Rails::Railtie' do
  let(:railtie_path) do
    File.expand_path('../../lib/testsift/rails/railtie.rb', __dir__)
  end

  # The dev Gemfile does not include Rails, so a real ::Rails::Railtie
  # is not in the object graph. Provide a minimal stand-in that records
  # every `initializer(name, &block)` call so the spec can inspect what
  # the loaded railtie.rb registered. Full fixture-level boot happens
  # in the Rails integration matrix.
  let(:railtie_base) do
    Class.new do
      class << self
        def initializer(name, &block)
          registered_initializers[name] = block
        end

        def registered_initializers
          @registered_initializers ||= {}
        end
      end
    end
  end

  before do
    stub_const('Rails', Module.new) unless defined?(Rails)
    stub_const('Rails::Railtie', railtie_base)

    # rubocop:disable RSpec/RemoveConst
    TestSift::Rails.send(:remove_const, :Railtie) if TestSift::Rails.const_defined?(:Railtie, false)
    # rubocop:enable RSpec/RemoveConst

    load railtie_path
  end

  it 'defines the class under TestSift::Rails' do
    expect(TestSift::Rails.const_defined?(:Railtie, false)).to be(true)
  end

  it 'subclasses the provided Rails::Railtie base' do
    expect(TestSift::Rails::Railtie).to be < railtie_base
  end

  it 'registers exactly one initializer named testsift.setup' do
    expect(TestSift::Rails::Railtie.registered_initializers.keys)
      .to contain_exactly('testsift.setup')
  end

  it 'logs a confirmation line when the initializer block runs' do
    allow(TestSift.logger).to receive(:info)

    TestSift::Rails::Railtie.registered_initializers['testsift.setup'].call

    expect(TestSift.logger).to have_received(:info)
      .with(/testsift Rails integration loaded/)
  end
end
