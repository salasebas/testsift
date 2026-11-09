# frozen_string_literal: true

module PerformanceEvidence
  class Corpus
    PRESETS = {
      'sparse' => { files: 100, branch_sites: 8, examples: 1000, fanout: 1, inputs: 100, eager: false },
      'dense' => { files: 100, branch_sites: 32, examples: 1000, fanout: 20, inputs: 500, eager: false },
      'eager' => { files: 500, branch_sites: 32, examples: 1000, fanout: 1, inputs: 1000, eager: true },
      'large' => { files: 100, branch_sites: 8, examples: 10_000, fanout: 1, inputs: 1000, eager: false }
    }.freeze

    attr_reader :dimensions

    def initialize(dimensions)
      @dimensions = dimensions
      sizes = dimensions.values_at(:files, :branch_sites, :examples, :fanout, :inputs)
      raise ArgumentError, 'positive corpus sizes required' unless sizes.all? do |value|
        value.is_a?(Integer) && value.positive?
      end
      raise ArgumentError, 'fanout exceeds files' if dimensions.fetch(:fanout) > dimensions.fetch(:files)
      raise ArgumentError, 'eager must be boolean' unless [true, false].include?(dimensions.fetch(:eager))
    end

    def write(root)
      %w[app spec inputs].each do |directory|
        FileUtils.rm_rf(File.join(root, directory))
        FileUtils.mkdir_p(File.join(root, directory))
      end
      dimensions.fetch(:files).times do |index|
        File.write(File.join(root, "app/work_#{index}.rb"), source(index))
      end
      dimensions.fetch(:inputs).times do |index|
        File.write(File.join(root, "inputs/input_#{index}.json"), "{\"value\":1}\n")
      end
      File.write(File.join(root, '.testsift'), configuration)
      File.write(File.join(root, 'spec/spec_helper.rb'), helper)
      4.times { |shard| File.write(File.join(root, "spec/work_#{shard}_spec.rb"), spec(shard)) }
      File.write(File.join(root, 'corpus.json'), JSON.pretty_generate(dimensions))
    end

    private

    def source(index)
      body = "value += 1 if x >= 0\n" * dimensions.fetch(:branch_sites)
      "module ScaleWork#{index}\ndef self.call(x)\nvalue = 0\n#{body}value\nend\nend\n"
    end

    def configuration
      "TestSift.configure do\n  coverage_track_files 'app/**/*.rb'\nend\n"
    end

    def helper
      if dimensions.fetch(:eager)
        eager = "Dir[File.expand_path('../app/*.rb', __dir__)].sort.each { |path| require path }"
      end
      <<~RUBY
        require 'json'
        if ENV['EVIDENCE_TRACER'] == '1'
          require 'testsift'
          TestSift.start
        end
        #{eager}
      RUBY
    end

    def spec(shard)
      <<~RUBY
        require 'spec_helper'
        RSpec.describe 'scale #{shard}' do
          #{dimensions.fetch(:examples)}.times do |index|
            next unless index % 4 == #{shard}
            it("example \#{index}") do
              #{dimensions.fetch(:fanout)}.times do |offset|
                file = (index + offset) % #{dimensions.fetch(:files)}
                require File.expand_path("../app/work_\#{file}", __dir__)
                expect(Object.const_get("ScaleWork\#{file}").call(1)).to eq(#{dimensions.fetch(:branch_sites)})
              end
              input = index % #{dimensions.fetch(:inputs)}
              data = JSON.parse(File.read(File.expand_path("../inputs/input_\#{input}.json", __dir__)))
              expect(data.fetch('value')).to eq(1)
            end
          end
        end
      RUBY
    end
  end
end
