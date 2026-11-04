# frozen_string_literal: true

require 'digest'
require 'json'
require 'open3'
require 'optparse'
require 'tmpdir'
require_relative 'coverage'

module RuntimeEvidence
  def self.main
    options = { rubies: [RbConfig.ruby], output: nil }
    OptionParser.new do |flags|
      flags.on('--rubies LIST', Array) { |value| options[:rubies] = value }
      flags.on('--output PATH') { |value| options[:output] = value }
    end.parse!
    raise ArgumentError, 'new output path required' if !options[:output] || File.exist?(options[:output])

    rows = options.fetch(:rubies).product(%w[off lines branches tracepoint], [1, 200],
                                          [false, true]).map do |ruby, mode, touched, jit|
      sample(ruby, mode, touched, jit)
    end
    payload = { driver_sha256: Digest::SHA256.file(__FILE__).hexdigest,
                workload_sha256: Digest::SHA256.file(File.join(__dir__, 'coverage.rb')).hexdigest,
                options: options, rows: rows }
    File.write(options.fetch(:output), JSON.pretty_generate(payload))
  end

  def self.sample(ruby, mode, touched, jit)
    Dir.mktmpdir('testsift-runtime') do |root|
      resource = File.join(root, 'time.txt')
      command = ['/usr/bin/time', '-f', '%M', '-o', resource, ruby]
      command.push('--yjit', '--yjit-call-threshold=1') if jit
      command.push(__FILE__, '--child')
      env = { 'FILES' => '200', 'BRANCH_SITES' => '32', 'ITERATIONS' => '20',
              'MODE' => mode, 'TOUCHED' => touched.to_s, 'RUBYOPT' => nil }
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      stdout, stderr, status = Open3.capture3(env, *command)
      raise "runtime comparison failed: #{command.inspect}: #{stderr}" unless status.success?

      JSON.parse(stdout).merge(command: command, env: env, ruby_sha256: Digest::SHA256.file(ruby).hexdigest,
                               command_seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
                               peak_rss_kib: File.read(resource).strip.to_i)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV == ['--child']
    CoverageEvidence.prepend(Module.new do
      private

      def prepare(root)
        super
        3.times { execute(@workloads) }
      end

      def result
        jit = defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
        super.merge(yjit_enabled: jit, yjit_stats: jit ? RubyVM::YJIT.runtime_stats : nil)
      end
    end)
    CoverageEvidence.new.run
  else
    RuntimeEvidence.main
  end
end
