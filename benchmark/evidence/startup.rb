# frozen_string_literal: true

require_relative 'current'

module StartupEvidence
  def metadata
    data = super
    data.fetch(:driver_sha256)['startup.rb'] = Digest::SHA256.file(__FILE__).hexdigest
    data.merge(unwrapped_dry_run: true,
               unwrapped_contract: 'RSpec discovery without examples, tracing, Coverage, or benchmark bootstrap')
  end

  def invocation(scenario, directory)
    args = super
    args << '--dry-run' if scenario == 'unwrapped_plain'
    args
  end
end

PerformanceEvidence::CurrentRunner.prepend(StartupEvidence)
PerformanceEvidence.current_main if $PROGRAM_NAME == __FILE__
