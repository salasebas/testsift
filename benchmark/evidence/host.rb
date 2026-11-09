# frozen_string_literal: true

require 'fiddle'
require 'open3'

module PerformanceEvidence
  # Platform-specific process accounting for the evidence drivers. Linux keeps the
  # published protocol (GNU time, /proc, taskset); macOS uses BSD time -l, sysctl,
  # and getrusage. Other platforms are rejected instead of producing partial rows.
  module Host
    PLATFORMS = { 'linux' => :linux, 'darwin' => :macos }.freeze

    module_function

    def platform
      PLATFORMS.find { |name, _| RUBY_PLATFORM.include?(name) }&.last ||
        raise("unsupported benchmark platform: #{RUBY_PLATFORM}; use Linux or macOS")
    end

    def timed(args, output)
      case platform
      when :linux then ['/usr/bin/time', '-f', '%M %U %S', '-o', output, *args]
      when :macos then ['/usr/bin/time', '-l', '-o', output, *args]
      end
    end

    # Returns peak single-process RSS in KiB plus user and system CPU seconds.
    def resources(output)
      text = File.read(output)
      case platform
      when :linux
        rss, user, system = text.lines.last.split.map(&:to_f)
        { peak_rss_kib: rss, user_seconds: user, system_seconds: system }
      when :macos
        times = text.match(/([\d.]+) real\s+([\d.]+) user\s+([\d.]+) sys/) || raise("unreadable time output: #{output}")
        rss = text[/(\d+)\s+maximum resident set size/, 1] || raise("missing peak RSS: #{output}")
        { peak_rss_kib: rss.to_f / 1024, user_seconds: times[2].to_f, system_seconds: times[3].to_f }
      end
    end

    def description
      case platform
      when :linux
        { kernel: capture('uname', '-srmo'),
          cpu: File.read('/proc/cpuinfo').lines.grep(/^model name/).first&.strip,
          memory: File.read('/proc/meminfo').lines.first.strip,
          cpu_affinity: capture('taskset', '-pc', Process.pid.to_s) }
      when :macos
        { kernel: capture('uname', '-srm'), cpu: capture('sysctl', '-n', 'machdep.cpu.brand_string'),
          memory: "hw.memsize: #{capture('sysctl', '-n', 'hw.memsize')} bytes",
          cpu_affinity: "unsupported on macOS; hw.ncpu=#{capture('sysctl', '-n', 'hw.ncpu')}" }
      end
    end

    # Peak RSS of the current process in KiB, read from inside the measured command.
    def process_peak_rss_kib
      case platform
      when :linux then File.read('/proc/self/status')[/^VmHWM:\s+(\d+)/, 1].to_i
      when :macos then self_rusage_max_rss_bytes / 1024
      end
    end

    RUSAGE_SELF = 0
    # struct rusage begins with two struct timeval fields (16 bytes each on
    # 64-bit Darwin); ru_maxrss follows and is reported in bytes there.
    RUSAGE_SIZE = 144
    RUSAGE_MAXRSS_OFFSET = 32

    def self_rusage_max_rss_bytes
      @getrusage ||= Fiddle::Function.new(Fiddle::Handle::DEFAULT['getrusage'],
                                          [Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      buffer = Fiddle::Pointer.malloc(RUSAGE_SIZE, Fiddle::RUBY_FREE)
      raise 'getrusage failed' unless @getrusage.call(RUSAGE_SELF, buffer).zero?

      buffer[RUSAGE_MAXRSS_OFFSET, Fiddle::SIZEOF_LONG].unpack1('q')
    end

    def capture(*args)
      output, status = Open3.capture2e(*args)
      raise "#{args.inspect} failed (#{status.exitstatus}):\n#{output}" unless status.success?

      output.strip
    end
  end
end
