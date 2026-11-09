# frozen_string_literal: true

require 'json'

require_relative 'validation'

module OSSBenchmark
  # Summaries use only measured rounds; preflight, oracle, and prime rows stay
  # in runs.jsonl. Percentiles use the nearest rank, ceil(n * p), over valid
  # samples, matching benchmark/evidence.
  module Report
    CELL_KEYS = %i[project suite case tracer variant].freeze

    module_function

    def percentile(values, fraction)
      sorted = values.compact.sort
      return nil if sorted.empty?

      sorted.fetch((fraction * sorted.size).ceil - 1)
    end

    def summarize(rows, projects, failures)
      measured = rows.select { |row| row[:round].is_a?(Integer) }
      failures += projects.values.flat_map { |state| state.fetch(:failures) }
      problems = (failures + rows.select { |row| problem?(row) }.map { |row| problem(row) }).uniq
      { valid: problems.empty?, problems: problems,
        cells: measured.group_by { |row| row.values_at(*CELL_KEYS) }.map { |key, samples| cell(key, samples) },
        comparisons: compare(measured), oracles: oracle_summary(projects),
        seeds: projects.transform_values { |state| state.fetch(:seeds) } }
    end

    def oracle_summary(projects)
      projects.transform_values do |state|
        state.fetch(:oracles).transform_values { |oracle| oracle.slice(:total, :failures) }
      end
    end

    def problem?(row)
      !row[:valid] || row[:missed_failures].to_a.any? || row[:status_mismatches].to_a.any?
    end

    def problem(row)
      row.slice(:project, :case, :tracer, :variant, :round, :errors, :missed_failures, :status_mismatches)
    end

    def cell(key, samples)
      valid = samples.select { |row| row[:valid] }
      CELL_KEYS.zip(key).to_h.merge(
        samples: samples.size, valid_samples: valid.size,
        p50_seconds: percentile(valid.map { _1[:wall_seconds] }, 0.5),
        p95_seconds: percentile(valid.map { _1[:wall_seconds] }, 0.95),
        p50_peak_rss_kib: percentile(valid.map { _1[:peak_rss_kib] }, 0.5),
        p50_allocations: percentile(valid.map { _1[:allocations] }, 0.5),
        p50_cache_bytes: percentile(valid.map { _1[:cache_bytes] }, 0.5),
        p50_report_bytes: percentile(valid.map { _1[:report_bytes] }, 0.5),
        **selection(valid), **correctness(samples)
      )
    end

    def selection(valid)
      { executed: valid.map { _1[:executed] }.minmax, total: valid.map { _1[:total] }.uniq,
        selected_ratio: valid.filter_map { _1[:selected_ratio] }.minmax,
        unexecuted_by_tracer: valid.filter_map { _1[:unexecuted] }.max }
    end

    def correctness(samples)
      { missed_failures: samples.sum { _1[:missed_failures].to_a.size },
        status_mismatches: samples.sum { _1[:status_mismatches].to_a.size },
        errors: samples.flat_map { _1[:errors] }.uniq }
    end

    # Each tracer must select the same set in every round of a case, and the
    # two tracers are compared with each other.
    def compare(rows)
      traced = rows.select { |row| row[:tracer] && row[:valid] }
      traced.group_by { |row| row.values_at(:project, :case, :variant) }.map do |(project, kase, variant), samples|
        sets = selections(samples)
        { project: project, case: kase, variant: variant,
          selected: sets.transform_values { |list| list.map(&:size) },
          deterministic: sets.transform_values(&:one?), **agreement(sets) }
      end
    end

    def selections(samples)
      samples.group_by { |row| row[:tracer] }.transform_values do |list|
        list.map { |row| Validation.executed_ids(row) }.uniq
      end
    end

    def agreement(sets)
      return {} unless sets.size == 2 && sets.values.all?(&:one?)

      first, second = sets.keys
      a = sets.fetch(first).first
      b = sets.fetch(second).first
      { identical: a == b, only_counts: { first => (a - b).size, second => (b - a).size },
        only: { first => (a - b).sort.first(20), second => (b - a).sort.first(20) } }
    end

    def markdown(summary, metadata)
      lines = ["# OSS benchmark #{metadata[:recorded_at]}", '',
               "Host: #{metadata[:cpu]}, #{metadata[:memory]}, #{metadata[:kernel]}. Docker #{metadata[:docker]}.",
               "TestSift: #{metadata[:testsift].slice(:source, :version, :revision).values.join(' ')}. " \
               "rspec-tracer: #{metadata.dig(:rspec_tracer, :version)}.", '']
      summary[:cells].group_by { _1[:project] }.each do |project, cells|
        lines.concat(project_section(project, cells, metadata.dig(:projects, project)))
        lines.concat(comparison_section(summary[:comparisons].select { _1[:project] == project }))
      end
      lines.concat(problem_section(summary[:problems]))
      "#{lines.join("\n")}\n"
    end

    def project_section(project, cells, info)
      plain = cells.find { _1[:case] == 'plain' }&.fetch(:p50_seconds)
      lines = ["## #{project}", '']
      if info
        lines << "#{info[:repository]} `#{info[:tag]}` (`#{info[:commit]}`), #{info[:ruby]}, " \
                 "suite `#{info[:suite]}`, runner `#{info.dig(:runner, 'name')}`, " \
                 "#{info[:expected_processes]} RSpec process(es)." << ''
      end
      lines << '| Case | Tracer | Change | Valid/n | p50 s | p95 s | p50 / plain | Executed / oracle | ' \
               'Missed failures | p50 peak RSS MiB |' << '|---|---|---|---|---|---|---|---|---|---|'
      cells.sort_by { [_1[:tracer].to_s, _1[:case], _1[:variant].to_s] }.each { lines << cell_row(_1, plain) }
      lines << ''
    end

    def cell_row(cell, plain)
      relative = plain && cell[:p50_seconds] ? format('%.2fx', cell[:p50_seconds] / plain) : 'n/a'
      rss = cell[:p50_peak_rss_kib] ? format('%.0f', cell[:p50_peak_rss_kib] / 1024) : 'n/a'
      executed = "#{cell[:executed].uniq.join('-')} / #{cell[:total].join(',')} (#{ratio(cell[:selected_ratio])})"
      "| #{cell[:case]} | #{cell[:tracer] || '-'} | #{cell[:variant] || '-'} | " \
        "#{cell[:valid_samples]}/#{cell[:samples]} | #{seconds(cell[:p50_seconds])} | " \
        "#{seconds(cell[:p95_seconds])} | #{relative} | #{executed} | #{cell[:missed_failures]} | #{rss} |"
    end

    def comparison_section(entries)
      entries = entries.select { _1.key?(:identical) }
      return [] if entries.empty?

      lines = ['| Case | Change | Selected per tracer | Identical |', '|---|---|---|---|']
      entries.each do |entry|
        counts = entry[:selected].map { |tracer, sizes| "#{tracer} #{sizes.join('/')}" }.join(', ')
        detail = if entry[:identical]
                   'yes'
                 else
                   "no (only #{entry[:only_counts].map do |tracer, count|
                     "#{tracer} #{count}"
                   end.join(', ')})"
                 end
        lines << "| #{entry[:case]} | #{entry[:variant] || '-'} | #{counts} | #{detail} |"
      end
      lines << ''
    end

    def problem_section(problems)
      return [] if problems.empty?

      ['## Problems', '', *problems.map { "- `#{JSON.generate(_1)[0, 600]}`" }, '']
    end

    def seconds(value)
      value ? format('%.1f', value) : 'n/a'
    end

    def ratio(range)
      return 'n/a' if range.compact.empty?

      low, high = range.map { |value| format('%.1f%%', value * 100) }
      low == high ? low : "#{low}-#{high}"
    end
  end
end
