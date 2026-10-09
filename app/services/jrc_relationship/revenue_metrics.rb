# A fixed opening cohort excludes newly acquired customers from NRR/GRR.
class JrcRelationship::RevenueMetrics
  def self.call(opening:, closing:)
    cohort = opening.select { |_id, value| value.is_a?(Numeric) && value.positive? }
    return unavailable_result(cohort, closing) if incomplete_cohort?(cohort, closing)

    calculation = revenue_calculation(cohort, closing)
    result(calculation, cohort.size)
  end

  def self.incomplete_cohort?(cohort, closing)
    cohort.empty? || cohort.keys.any? { |id| !closing[id].is_a?(Numeric) || closing[id].negative? }
  end

  def self.unavailable_result(cohort, closing)
    { nrr: nil, gross_retention: nil, revenue_churn: nil, revenue_churn_cents: nil, cohort_customers: cohort.size,
      revenue_calculation: { opening_cents: cohort.values.sum.presence, denominator_cents: cohort.values.sum.presence,
                             opening_customers: cohort.size, closing_customers: cohort.count { |id, _| closing[id].is_a?(Numeric) },
                             reason: cohort.empty? ? 'opening_cohort_empty' : 'closing_cohort_incomplete' } }
  end

  def self.revenue_calculation(cohort, closing)
    base = cohort.values.sum
    current = cohort.keys.sum { |id| closing.fetch(id) }
    retained = cohort.sum { |id, value| [closing.fetch(id), value].min }
    { opening_cents: base, closing_cents: current, retained_cents: retained, lost_cents: base - retained,
      denominator_cents: base, opening_customers: cohort.size, closing_customers: cohort.size }
  end

  def self.result(calculation, cohort_size)
    base = calculation[:opening_cents]
    { nrr: (100.0 * calculation[:closing_cents] / base).round(2), gross_retention: (100.0 * calculation[:retained_cents] / base).round(2),
      revenue_calculation: calculation, revenue_churn: (100.0 * calculation[:lost_cents] / base).round(2),
      revenue_churn_cents: calculation[:lost_cents], cohort_customers: cohort_size }
  end

  private_class_method :incomplete_cohort?, :unavailable_result, :revenue_calculation, :result
end
