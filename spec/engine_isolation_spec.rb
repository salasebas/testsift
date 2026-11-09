# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe TestSift::Engine do
  it 'loads and exercises the engine in a Ruby process without RSpec' do
    output, status = Open3.capture2e(
      RbConfig.ruby, '-Ilib', 'spec/core/engine_lifecycle.rb'
    )

    expect(status.success?).to be(true), output
  end
end
