# frozen_string_literal: true

# Only the latest original analysis contributes once. Human reviews remain
# separate records; missing/unknown labels are never assigned a sentiment.
class JrcContactCenter::RecordingQualityMetrics
  SENTIMENTS = %w[positivo neutro negativo].freeze
  FILTERS = (SENTIMENTS + %w[unclassified without_analysis]).freeze

  def initialize(rows:, call_ids:)
    @rows = rows
    @call_ids = call_ids.uniq
  end

  def summary
    counts = SENTIMENTS.index_with { |sentiment| @rows.values.count { |row| classification(row) == sentiment } }
    analyzed = @rows.length
    { universe: @call_ids.length, analyzed: analyzed, without_analysis: @call_ids.length - analyzed,
      unclassified: analyzed - counts.values.sum, counts: counts, denominator: 'latest_original_analyses',
      percentages: counts.transform_values { |count| analyzed.positive? ? (100.0 * count / analyzed).round(2) : nil } }.merge(quality_summary)
  end

  def selected_ids(filter)
    return @call_ids if filter.nil? || filter == ''

    raise JrcContactCenter::OperationError, 'invalid_recording_filter' unless filter.is_a?(String) && FILTERS.include?(filter)

    @call_ids.select { |id| selected_row?(@rows[id], filter) }
  end

  def present(id)
    row = @rows[id]
    return { available: false, sentiment: nil, quality_score: nil } unless row

    { available: true, sentiment: classification(row), quality_score: quality_score(row), observed_at: row.fetch('analise_criada_em') }
  end

  private

  def quality_summary
    scores = @rows.values.filter_map { |row| quality_score(row) }
    { quality_measured: scores.length, quality_average: scores.any? ? (scores.sum.to_f / scores.length).round(2) : nil }
  end

  def selected_row?(row, filter)
    filter == 'without_analysis' ? row.nil? : row && classification(row) == filter
  end

  def classification(row)
    value = row['sentimento_cliente']
    return 'unclassified' unless value.is_a?(String)

    label = value.strip.downcase
    SENTIMENTS.include?(label) ? label : 'unclassified'
  end

  def quality_score(row)
    value = row['nota_final']
    value if value.is_a?(Numeric) && value.finite? && value.between?(0, 100)
  end
end
