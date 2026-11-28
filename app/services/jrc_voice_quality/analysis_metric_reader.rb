# frozen_string_literal: true

require 'time'
require 'timeout'
require 'uri'

# A thin read of the existing scoped view. Never fetch transcripts or interpret
# an unavailable provider as an empty dataset. No existing client caller changes.
class JrcVoiceQuality::AnalysisMetricReader < JrcVoiceQuality::SupabaseClient
  FIELDS = %w[account_id call_id analise_id analise_criada_em sentimento_cliente sentimento_atendente nota_final].freeze
  PAGE_SIZE = 200
  MAX_ROWS = 20_000
  MAX_PAGES = 100
  MAX_CALLS = 5_000
  MAX_BATCH_CALLS = 100
  MAX_QUERY_ID_BYTES = 4_000
  READ_SECONDS = 24

  def call(account_id:, call_ids:, observed_before:)
    account, ids = input!(account_id, call_ids, observed_before)
    return {} if ids.empty?

    raise_configuration! unless configured?
    budget = { rows: 0, deadline: clock + READ_SECONDS }
    batches(ids).each_with_object({}) do |batch, result|
      read_batch(account, batch, observed_before, budget).each { |id, row| result[id] = row }
    end
  end

  private

  def input!(account_id, call_ids, observed_before)
    ids = Array(call_ids).map { |id| resource_id!(id) }.uniq
    unavailable! unless ids.length <= MAX_CALLS && observed_before.is_a?(Time)

    [scope_id!(account_id), ids]
  end

  def batches(ids)
    size = 0
    ids.each_with_object([[]]) do |id, groups|
      bytes = URI.encode_www_form_component(%("#{id}")).bytesize + 3
      if groups.last.length >= MAX_BATCH_CALLS || size + bytes > MAX_QUERY_ID_BYTES
        groups << []
        size = 0
      end
      groups.last << id
      size += bytes
    end
  end

  def read_batch(account, ids, cutoff, budget)
    rows_read = 0
    latest = {}
    MAX_PAGES.times do
      unavailable! if clock >= budget.fetch(:deadline)
      rows = read_page(account, ids, cutoff, rows_read, budget)
      verify_page!(rows, budget)
      return latest if rows.empty?

      rows_read += rows.length
      rows.each { |row| retain_latest!(latest, row, account, ids, cutoff) }
    end
    unavailable!
  end

  def verify_page!(rows, budget)
    unavailable! unless rows.is_a?(Array) && rows.length <= PAGE_SIZE
    unavailable! if clock >= budget.fetch(:deadline)

    budget[:rows] += rows.length
    unavailable! if budget.fetch(:rows) > MAX_ROWS
  end

  def read_page(account, ids, cutoff, offset, budget)
    remaining = budget.fetch(:deadline) - clock
    unavailable! unless remaining.positive?

    Timeout.timeout(remaining) do
      request(:get, '/vw_qualidade_pabx_dashboard', query: query(account, ids, cutoff, offset), timeout: [remaining, 20].min)
    end
  rescue Timeout::Error
    unavailable!
  end

  def query(account, ids, cutoff, offset)
    { select: FIELDS.join(','), account_id: "eq.#{account}", call_id: "in.(#{postgrest_list(ids)})",
      analise_criada_em: "lte.#{cutoff.iso8601(6)}", order: 'call_id.asc,analise_criada_em.desc,analise_id.desc',
      limit: PAGE_SIZE, offset: offset }
  end

  def retain_latest!(latest, row, account, ids, cutoff)
    candidate = validated_metric!(row, account, ids, cutoff)
    id = row.fetch('call_id').to_s
    previous = latest[id]
    # The view may repeat an analysis through its native transcription join.
    unavailable! if previous && previous['analise_id'] == candidate['analise_id'] && previous != candidate
    latest[id] = candidate if !previous || newer?(candidate, previous)
  rescue KeyError, ArgumentError, TypeError
    unavailable!
  end

  def validated_metric!(row, account, ids, cutoff)
    verify_analysis_row!(row, account, ids)
    unavailable! unless row.keys.sort == FIELDS.sort

    analysis_id = resource_id!(row.fetch('analise_id'))
    timestamp = Time.iso8601(row.fetch('analise_criada_em'))
    unavailable! if timestamp > cutoff || !row['analise_criada_em'].is_a?(String)

    row.slice(*FIELDS).merge('analise_id' => analysis_id)
  end

  def newer?(candidate, previous)
    comparison = analysis_order(candidate) <=> analysis_order(previous)
    unavailable! if comparison.nil?
    comparison.positive?
  end

  def analysis_order(row)
    id = row.fetch('analise_id')
    [Time.iso8601(row.fetch('analise_criada_em')), id.match?(/\A[0-9]+\z/) ? id.to_i : id]
  end

  def clock
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def unavailable!
    raise JrcVoiceQuality::PersistenceError.new('Resumo de qualidade indisponível.', code: :summary_unavailable)
  end
end
