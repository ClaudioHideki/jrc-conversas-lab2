# Corporate criteria are distinct from personal Contact CustomFilters. Reuse the
# canonical company directory predicates, then intersect with the caller's scope.
class JrcCustomers::SegmentCriteria
  FIELDS = (%w[relationship_type person_kind segment owner_id economic_group active city size source state] +
            JrcCustomers::FinancialSegmentCriteria::FIELDS).freeze
  OPERATORS = %w[equal_to not_equal_to].freeze

  def self.error(value, mode:)
    message = structure_error(value)
    return message if message
    return 'dynamic segments require at least one rule' if mode == 'dynamic' && value['rules'].empty?

    value['rules'].each do |rule|
      message = rule_error(rule)
      return message if message
    end
    nil
  end

  def self.structure_error(value)
    return 'must be an object' unless value.is_a?(Hash)
    return 'contains unsupported options' if (value.keys.map(&:to_s) - %w[match rules]).any?
    return 'match must be all or any' unless %w[all any].include?(value['match'])

    rules = value['rules']
    return 'must contain at most 20 rules' unless rules.is_a?(Array) && rules.size <= 20

    nil
  end

  def self.rule_error(rule)
    return 'contains an invalid rule' unless rule.is_a?(Hash) && (rule.keys - %w[field operator value period_start period_end]).empty?
    return JrcCustomers::FinancialSegmentCriteria.error(rule) if JrcCustomers::FinancialSegmentCriteria::FIELDS.include?(rule['field'])
    return 'periods are only supported for invoiced revenue' if rule.keys.intersect?(%w[period_start period_end])
    return 'contains an unsupported field or operator' unless FIELDS.include?(rule['field']) && OPERATORS.include?(rule['operator'])

    value_error(rule)
  end

  def self.value_error(rule)
    value = rule['value']
    return 'each rule requires a scalar value of at most 200 characters' unless scalar_value?(value)
    return 'active must be true or false' if rule['field'] == 'active' && %w[true false].exclude?(value)
    return 'owner_id must be a positive ID' if rule['field'] == 'owner_id' && !value.match?(/\A[1-9][0-9]*\z/)

    nil
  end

  def self.scalar_value?(value)
    value.is_a?(String) && value.present? && value.length <= 200
  end

  def initialize(account:, scope:, actor: nil)
    @account = account
    @scope = scope
    @actor = actor
  end

  def call(criteria)
    parts = criteria.fetch('rules').map do |rule|
      if JrcCustomers::FinancialSegmentCriteria::FIELDS.include?(rule['field'])
        next JrcCustomers::FinancialSegmentCriteria.new(account: @account, actor: @actor, scope: @scope).call(rule)
      end

      matched = matches(rule)
      rule['operator'] == 'not_equal_to' ? @scope.where.not(id: matched.reselect(:id)) : @scope.where(id: matched.reselect(:id))
    end
    parts.reduce { |result, part| criteria['match'] == 'any' ? result.or(part) : result.where(id: part.reselect(:id)) }
  end

  private

  def matches(rule)
    field, value = rule.values_at('field', 'value')
    return @scope.where(field => value) if %w[size source].include?(field)

    if %w[state city].include?(field)
      column = JrcCustomers::Address.arel_table[field]
      addresses = JrcCustomers::Address.where(account_id: @account.id).where(column.lower.eq(value.downcase)).select(:company_id)
      return @scope.where(id: addresses)
    end

    JrcCustomers::DirectoryQuery.new(account: @account, filters: { field => value }).call
  end
end
