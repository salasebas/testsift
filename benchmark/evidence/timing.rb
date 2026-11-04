# frozen_string_literal: true

require_relative 'current'

module TimingEvidence
  def metadata
    data = super
    %w[timing.rb timing_boot.rb].each do |file|
      data.fetch(:driver_sha256)[file] = Digest::SHA256.file(File.join(__dir__, file)).hexdigest
    end
    data.merge(profile_contract: 'exclusive timing without native allocator sampling')
  end

  def environment(*)
    super.merge('EVIDENCE_PROFILE_PURPOSE' => 'timing')
  end

  def invocation(scenario, directory)
    super.map do |argument|
      argument.gsub(PerformanceEvidence::CurrentRunner::BOOT, File.join(__dir__, 'timing_boot.rb'))
    end
  end
end

PerformanceEvidence.singleton_class.prepend(Module.new do
  def validate_current_options(options)
    if options.fetch(:repetitions).zero? && options.fetch(:profiles).positive?
      super(options.merge(repetitions: 1))
    else
      super
    end
  end
end)

PerformanceEvidence::CurrentRunner.prepend(TimingEvidence)
PerformanceEvidence.current_main if $PROGRAM_NAME == __FILE__
