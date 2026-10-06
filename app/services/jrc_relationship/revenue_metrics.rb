# A fixed opening cohort excludes newly acquired customers from NRR/GRR.
class JrcRelationship::RevenueMetrics
  def self.call(opening:, closing:)
    cohort = opening.select { |_id, value| value.is_a?(Numeric) && value.positive? }
    unavailable = { nrr: nil, gross_retention: nil, revenue_churn: nil, revenue_churn_cents: nil, cohort_customers: cohort.size }
    return unavailable if cohort.empty? || cohort.keys.any? { |id| !closing[id].is_a?(Numeric) || closing[id].negative? }

    base = cohort.values.sum
    current = cohort.keys.sum { |id| closing.fetch(id) }
    retained = cohort.sum { |id, value| [closing.fetch(id), value].min }
    lost = base - retained
    { nrr: (100.0 * current / base).round(2), gross_retention: (100.0 * retained / base).round(2),
      revenue_churn: (100.0 * lost / base).round(2), revenue_churn_cents: lost, cohort_customers: cohort.size }
  end
end
