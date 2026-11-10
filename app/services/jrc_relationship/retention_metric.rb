require 'bigdecimal'

# Cohort metric only. Persistence and authorization are outside this pure kernel.
# Opening and closing contain historical states keyed by the same native customer.
class JrcRelationship::RetentionMetric
  def self.call(opening:, closing:, policy:, complete:, authorized: true)
    return unavailable('insufficient_history') unless complete
    return unavailable('scope_unavailable') unless authorized
    rule = JrcRelationship::RetentionPolicy.normalize!(policy)
    return unavailable('invalid_history') unless opening.is_a?(Array) && closing.is_a?(Array)
    return unavailable('ambiguous_history') unless unique?(opening) && unique?(closing)
    first = opening.to_h { |row| [row.fetch('customer_key'), row] }
    last = closing.to_h { |row| [row.fetch('customer_key'), row] }
    eligibility = first.transform_values { |row| JrcRelationship::RetentionPolicy.eligible?(row, rule) }
    return unavailable('insufficient_history') if eligibility.value?(nil)
    cohort = eligibility.select { |_, eligible| eligible }.keys
    return unavailable('not_applicable', initial: 0) if cohort.empty?
    outcomes = cohort.map { |key| last.key?(key) ? JrcRelationship::RetentionPolicy.eligible?(last[key], rule) : nil }
    return unavailable('insufficient_history') if outcomes.include?(nil)
    retained = outcomes.count(true)
    percentage = ((BigDecimal(retained.to_s) * 100) / cohort.length).round(2).to_f
    { available: true, code: 'available', value: percentage, initial: cohort.length,
      retained: retained, exits: cohort.length - retained, target_percent: rule['target_percent'],
      definition: 'initial_eligible_customers_retained_at_period_end' }
  end

  def self.unique?(rows)
    keys = rows.map { |row| row.is_a?(Hash) ? row['customer_key'] : nil }
    keys.all? { |key| key.is_a?(String) && key.match?(/\A(company|contact):[1-9][0-9]*\z/) } && keys.uniq.length == keys.length
  end
  private_class_method :unique?

  def self.unavailable(code, initial: nil)
    { available: false, code: code, value: nil, initial: initial, retained: nil, exits: nil,
      target_percent: nil, definition: 'initial_eligible_customers_retained_at_period_end' }
  end
end
