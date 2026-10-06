class JrcRelationship::PlaybookConditions
  IDENTITY_FIELDS = %w[segment_id product_id business_unit_id].freeze
  FIELDS = %w[segment_id product_id business_unit_id health_score mrr_cents days_without_contact critical_tickets sla_breached nps csat overdue_cents delayed_projects].freeze
  OPERATORS = %w[lt lte eq gte gt].freeze

  def self.valid?(conditions)
    conditions.is_a?(Array) && conditions.size <= 20 && conditions.all? do |condition|
      condition.is_a?(Hash) && FIELDS.include?(condition['field']) && OPERATORS.include?(condition['operator']) &&
        Float(condition['value'], exception: false)&.finite? &&
        (!IDENTITY_FIELDS.include?(condition['field']) ||
          (condition['operator'] == 'eq' && Float(condition['value']).positive? && Float(condition['value']) == Float(condition['value']).to_i))
    end
  end

  def self.match?(conditions, signals)
    return false unless valid?(conditions)
    conditions.all? do |condition|
      if IDENTITY_FIELDS.include?(condition['field'])
        values = condition['field'] == 'product_id' ? Array(signals[:products]).map { |row| row[:id] || row['id'] } + [signals[:product_id]] :
          [signals[condition['field'].to_sym]]
        next values.any? { |value| Float(value, exception: false) == Float(condition['value']) }
      end
      raw = condition['field'] == 'health_score' ? signals.dig(:health, :score) : signals[condition['field'].to_sym]
      value = Float(raw, exception: false)
      target = Float(condition['value'])
      next false unless value&.finite?
      case condition['operator']
      when 'lt' then value < target
      when 'lte' then value <= target
      when 'eq' then value == target
      when 'gte' then value >= target
      when 'gt' then value > target
      end
    end
  end
end
