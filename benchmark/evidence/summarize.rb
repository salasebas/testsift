# frozen_string_literal: true

require 'json'
require 'zlib'

module CurrentEvidenceSummary
  COMPONENTS = {
    snapshot_production: %w[coverage_snapshot],
    normalization: %w[coverage_normalize],
    scans: %w[dependency_delta report_delta],
    attribution_hooks: %w[loaded_attribution file_attribution io_hooks example_boundary example_registration],
    stat_hash_discovery: %w[filesystem_stat sha256 stat_hash declared_globs new_files change_detection],
    graph_index: %w[graph graph_index graph_restore selection],
    decode_interning: %w[cache_decode cache_json_decode cache_intern cache_model cache_codec_decode],
    cache_load: %w[cache_load],
    snapshot_building: %w[snapshot_build],
    serialization_save: %w[cache_save cache_json_encode cache_codec_encode],
    reports: %w[reports coverage_report json_encode branch_report],
    worker_wait_merge: %w[worker_wait worker_merge worker_finalize],
    runner_setup_discovery: %w[runner_setup discovery]
  }.freeze

  def self.percentile(values, fraction)
    return nil if values.empty?

    sorted = values.sort
    sorted.fetch((sorted.size * fraction).ceil - 1)
  end

  def self.distribution(values)
    { p50: percentile(values.compact, 0.5), p95: percentile(values.compact, 0.95) }
  end

  def self.profiles(rows)
    COMPONENTS.transform_values do |labels|
      seconds = rows.map { |row| component_seconds(row, labels) }
      { seconds: distribution(seconds),
        profile_wall_fraction: distribution(rows.zip(seconds).filter_map do |row, cost|
          cost.fdiv(row.fetch('wall_seconds')) if row.fetch('telemetry').size == 1
        end),
        allocations: distribution(rows.map { |row| component_allocations(row, labels) }) }
    end
  end

  def self.component_seconds(row, labels)
    row.fetch('telemetry').sum do |worker|
      labels.sum { |label| worker.fetch('metrics').fetch(label, {}).fetch('seconds', 0) }
    end
  end

  def self.component_allocations(row, labels)
    row.fetch('telemetry').sum do |worker|
      labels.sum { |label| worker.fetch('metrics').fetch(label, {}).fetch('allocations', 0) }
    end
  end

  def self.cell(key, rows)
    { fixture: key[0], mode: key[1], scenario: key[2], profile: key[3], samples: rows.size,
      wall_seconds: distribution(rows.map { |row| row.fetch('wall_seconds') }),
      allocations: distribution(rows.map { |row| row.fetch('allocations') }),
      cache_bytes: distribution(rows.map { |row| row.fetch('cache_bytes') }),
      report_bytes: distribution(rows.map { |row| row.fetch('report_bytes') }),
      selected_ratio: rows.map { |row| row.fetch('selected_ratio') }.minmax,
      components: key[3] ? profiles(rows) : nil }.merge(memory(rows)).merge(correctness(rows))
  end

  def self.memory(rows)
    { peak_rss_kib: distribution(rows.map { |row| row.fetch('peak_rss_kib') }),
      sampled_malloc_peak_bytes: distribution(rows.map do |row|
        row.fetch('telemetry').filter_map { |worker| worker['sampled_malloc_peak_bytes'] }.max
      end) }
  end

  def self.correctness(rows)
    {
      omitted_failures: rows.sum { |row| row.fetch('omitted_failing_tests').size },
      oracle_failures: rows.sum { |row| row.fetch('oracle_failure_ids').size },
      status_mismatches: rows.sum { |row| row.fetch('failure_status_mismatches').size }
    }
  end

  def self.read_rows(directory)
    plain = File.join(directory, 'runs.jsonl')
    return File.readlines(plain).map { |line| JSON.parse(line) } if File.file?(plain)

    Zlib::GzipReader.open("#{plain}.gz") { |file| file.each_line.map { |line| JSON.parse(line) } }
  end

  def self.main
    raise ArgumentError, 'supply dataset directories' if ARGV.empty?

    result = ARGV.to_h do |directory|
      rows = read_rows(directory)
      cells = rows.group_by { |row| row.values_at('fixture', 'mode', 'scenario', 'profile') }
      [File.basename(directory).delete_prefix('issue20-'), cells.map { |key, samples| cell(key, samples) }]
    end
    puts JSON.pretty_generate(result)
  end
end

CurrentEvidenceSummary.main if $PROGRAM_NAME == __FILE__
