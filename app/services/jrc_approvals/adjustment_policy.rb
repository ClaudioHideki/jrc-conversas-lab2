# Server-defined field vocabulary, configured bounds; no client model paths/eval.
class JrcApprovals::AdjustmentPolicy
  FIELDS = { 'discount_cents' => 'integer', 'payment_condition' => 'choice', 'payment_method' => 'choice',
    'installments_count' => 'integer', 'first_billing_days' => 'integer', 'first_due_date' => 'date' }.freeze
  SOURCES = {
    'crm.proposal_send' => %w[discount_cents], 'crm.proposal_convert' => %w[discount_cents],
    'crm.order_price' => %w[discount_cents], 'crm.price_exception' => %w[discount_cents],
    'crm.proposal_terms' => %w[payment_condition payment_method installments_count first_billing_days],
    'crm.order_terms' => %w[payment_condition payment_method installments_count first_due_date]
  }.freeze

  def self.validate!(input, key)
    raise JrcApprovals::Error, 'INVALID_ADJUSTMENT_POLICY' unless input.is_a?(Hash) && input.keys.sort == %w[fields schema_version] && input['schema_version'] == 1
    rows = input['fields']
    allowed = SOURCES.fetch(key, [])
    raise JrcApprovals::Error, 'INVALID_ADJUSTMENT_POLICY' unless rows.is_a?(Hash) && rows.any? && (rows.keys - allowed).empty?
    rows.each do |field, rule|
      raise JrcApprovals::Error, 'INVALID_ADJUSTMENT_POLICY' unless rule.is_a?(Hash)
      case FIELDS.fetch(field)
      when 'integer'
        valid = rule.keys.sort == %w[max min] && [rule['min'], rule['max']].all? { |value| value.is_a?(Integer) && value.between?(0, field == 'discount_cents' ? 9_007_199_254_740_991 : 2_147_483_647) } && rule['min'] <= rule['max']
        valid &&= rule['min'] >= 1 if field == 'installments_count'
      when 'choice'
        values = rule['options']
        valid = rule.keys == ['options'] && values.is_a?(Array) && values.size.between?(1, 50) && values.uniq == values &&
          values.all? { |value| value.is_a?(String) && value.match?(/\A[a-zA-Z0-9_-]{1,80}\z/) }
      when 'date'
        valid = rule.keys.sort == %w[max_days min_days] && [rule['min_days'], rule['max_days']].all? { |value| value.is_a?(Integer) && value.between?(0, 36_600) } && rule['min_days'] <= rule['max_days']
      end
      raise JrcApprovals::Error, 'INVALID_ADJUSTMENT_POLICY' unless valid
    end
    input
  end

  def self.validate_changes!(changes)
    raise JrcApprovals::Error, 'INVALID_ADJUSTMENT_FIELDS' unless changes.is_a?(Hash) && changes.any? && (changes.keys - FIELDS.keys).empty?
    changes.each do |key, value|
      valid = case FIELDS.fetch(key)
              when 'integer' then value.is_a?(Integer) && value.between?(0, key == 'discount_cents' ? 9_007_199_254_740_991 : 2_147_483_647)
              when 'choice' then value.is_a?(String) && value.match?(/\A[a-zA-Z0-9_-]{1,80}\z/)
              when 'date' then exact_date?(value)
              end
      raise JrcApprovals::Error, 'INVALID_ADJUSTMENT_FIELDS' unless valid
    end
    changes
  end

  def self.authorize!(definition, key, changes, today: Date.today)
    validate_changes!(changes)
    allowed = SOURCES.fetch(key, [])
    raise JrcApprovals::Error, 'ADJUSTMENT_NOT_SUPPORTED' unless (changes.keys - allowed).empty?
    rules = definition['adjustments']
    unless rules
      raise JrcApprovals::Error, 'ADJUSTMENT_CONFIGURATION_REQUIRED' unless changes.keys == ['discount_cents']
      return true # Explicitly installed legacy discount adapter, same native authority.
    end
    validate!(rules, key)
    changes.each do |field, value|
      rule = rules['fields'][field]
      raise JrcApprovals::Error, 'ADJUSTMENT_FIELD_NOT_AUTHORIZED' unless rule
      accepted = case FIELDS.fetch(field)
                 when 'integer' then value.between?(rule['min'], rule['max'])
                 when 'choice' then rule['options'].include?(value)
                 when 'date' then (Date.iso8601(value) - today).to_i.between?(rule['min_days'], rule['max_days'])
                 end
      raise JrcApprovals::Error, 'ADJUSTMENT_REQUIRES_HIGHER_POLICY' unless accepted
    end
    true
  end

  def self.exact_date?(value)
    value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/) && Date.iso8601(value).iso8601 == value
  rescue Date::Error
    false
  end
end
