# frozen_string_literal: true

require_relative 'run'

module PerformanceEvidence
  module InputFaultProbe
    def metadata
      super.merge(input_fault_probe: {
                    script_sha256: Digest::SHA256.file(__FILE__).hexdigest,
                    mutation: 'Flip Rails comments_enabled; change a Ruby spec expectation',
                    omissions_are_recorded: true
                  })
    end

    def mutate(fixture, scenario)
      return super unless scenario == 'fault'

      path = File.join(cwd(fixture), paths(fixture).fetch(:input))
      original = @originals.fetch(path)
      if fixture == 'rails'
        data = JSON.parse(original)
        data['comments_enabled'] = !data.fetch('comments_enabled')
        changed = "#{JSON.pretty_generate(data)}\n"
      else
        changed = original.sub('eq(80.0)', 'eq(81.0)')
      end
      raise 'input fault did not change bytes' if changed == original

      File.binwrite(path, changed)
    end

    def validate(row)
      return super unless row.fetch(:scenario) == 'fault'

      validate_discovery(row)
      raise "unexpected diagnostic exit: #{row}" unless [0, 1].include?(row.fetch(:exit_code))

      oracle = @oracles.fetch(row.values_at(:fixture, :mode))
      row[:mutation_kind] = 'semantic_input'
      row[:oracle_failure_ids] = oracle
      expected = oracle & row.fetch(:ids)
      observed = row.fetch(:failures)
      row[:failure_status_mismatches] = (expected - observed) + (observed - expected)
    end

    def run
      super
      omissions = @rows.sum { |row| row.fetch(:omitted_failing_tests).size }
      mismatches = @rows.sum { |row| row.fetch(:failure_status_mismatches, []).size }
      warn "Semantic input probe: #{omissions} omitted failure observations, #{mismatches} status mismatches"
      exit(1) if omissions.positive? || mismatches.positive?
    end
  end
end

PerformanceEvidence::Runner.prepend(PerformanceEvidence::InputFaultProbe)
PerformanceEvidence.main if $PROGRAM_NAME == __FILE__
