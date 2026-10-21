# frozen_string_literal: true

class JrcContactCenter::MetricsSummary
  def self.from_params(scope:, params:)
    from = Date.iso8601(params.fetch(:from, 30.days.ago.to_date.iso8601))
    to = Date.iso8601(params.fetch(:to, Time.zone.today.iso8601))
    raise ArgumentError, 'invalid report range' if to < from || (to - from).to_i > 366

    new(scope: scope, from: from, to: to)
  end

  def initialize(scope:, from:, to:)
    @scope = scope
    @from = from
    @to = to
  end

  def call
    facts = @scope.where(fact_date: @from..@to)
    totals = JrcContactCenter::DailyFact::COUNTERS.index_with { |column| facts.sum(column) }
    durations = JrcContactCenter::DailyFact::DURATIONS.index_with { |column| facts.sum(column) }
    totals.merge(durations).merge(averages(facts)).merge(from: @from, to: @to, sla: nil)
  end

  private

  def averages(facts)
    { tme_seconds: average(facts, 'wait_measured_count', 'wait_measured_seconds'),
      tma_seconds: average(facts, 'talk_measured_count', 'talk_measured_seconds'),
      acw_average_seconds: average(facts, 'acw_completed_count', 'acw_measured_seconds') }
  end

  def average(facts, key, total_key)
    count = facts.sum(Arel.sql("COALESCE((data ->> '#{key}')::bigint, 0)"))
    total = facts.sum(Arel.sql("COALESCE((data ->> '#{total_key}')::bigint, 0)"))
    count.positive? ? (total.to_f / count).round(2) : nil
  end
end
