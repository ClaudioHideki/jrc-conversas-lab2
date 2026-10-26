# frozen_string_literal: true

require 'time'

# Finite predicates shared by publication, simulation and native ticket intake.
# No scripts, network calls, writes, guessed priority or automatic AI decisions.
module JrcServiceDesk::OperationalRuleConditions
  module_function

  def validate!(row)
    if row.key?('conditions')
      root = row['conditions']
      exact!(root, %w[operator groups])
      operator!(root['operator'])
      raise ArgumentError, 'One to 20 condition groups required' unless root['groups'].is_a?(Array) && root['groups'].length.between?(1, 20)

      root['groups'].each do |group|
        exact!(group, %w[operator items])
        operator!(group['operator'])
        raise ArgumentError, 'One to 20 predicates required' unless group['items'].is_a?(Array) && group['items'].length.between?(1, 20)

        group['items'].each do |item|
          exact!(item, %w[field operator value])
          raise ArgumentError, 'Unsupported predicate' unless %w[eq neq].include?(item['operator'])

          JrcServiceDesk::OperationalRuleContract.predicates!(item['field'] => item['value'])
        end
      end
    end
    if row.key?('window')
      exact!(row['window'], %w[timezone conditions])
      JrcServiceDesk::SnapshotCalendar.new(timezone: row['window'].fetch('timezone'), conditions: row['window'].fetch('conditions'))
    end
    %w[valid_from valid_until].each { |key| Time.iso8601(row[key]) if row[key] }
    if row['valid_from'] && row['valid_until'] && Time.iso8601(row['valid_until']) <= Time.iso8601(row['valid_from'])
      raise ArgumentError, 'Validity end must follow its start'
    end
    raise ArgumentError, 'Explicit rule state required' if row.key?('enabled') && ![true, false].include?(row['enabled'])
    return unless row.key?('exceptions')

    data = row['exceptions']
    exact!(data, %w[company_ids contract_ids skip_assigned])
    %w[company_ids contract_ids].each do |field|
      ids = data[field]
      raise ArgumentError unless ids.is_a?(Array) && ids.length <= 100 && ids.uniq == ids

      ids.each { |id| JrcServiceDesk::OperationalRuleContract.integer!(id, 1, JrcServiceDesk::OperationalRuleContract::MAX_ID) }
    end
    raise ArgumentError unless [true, false].include?(data['skip_assigned'])
  rescue JrcServiceDesk::LifecycleDependencyError
    raise ArgumentError, 'Invalid explicit calendar configuration'
  end

  def match?(row, facts, now: Time.now.utc)
    return false if row['enabled'] == false
    return false if row['valid_from'] && now < Time.iso8601(row['valid_from'])
    return false if row['valid_until'] && now >= Time.iso8601(row['valid_until'])
    return false unless row.fetch('match').all? { |field, value| equal?(facts[field], value) }

    exceptions = row['exceptions']
    return false if exceptions && (exceptions['company_ids'].include?(facts['company_id']) ||
      exceptions['contract_ids'].include?(facts['contract_id']) || (exceptions['skip_assigned'] && facts['assigned'] == true))

    if row['window']
      calendar = JrcServiceDesk::SnapshotCalendar.new(timezone: row['window']['timezone'], conditions: row['window']['conditions'])
      return false unless calendar.elapsed(now, now + 1).positive?
    end
    root = row['conditions']
    return true unless root

    combine(root['operator'], root['groups'].map do |group|
      combine(group['operator'], group['items'].map do |item|
        # Missing input must never satisfy a negative predicate.
        next false unless available?(facts[item['field']], item['value'])

        equal = equal?(facts[item['field']], item['value'])
        item['operator'] == 'eq' ? equal : !equal
      end)
    end)
  end

  def predicates(row)
    row.fetch('match').map { |field, value| { 'field' => field, 'operator' => 'eq', 'value' => value } } +
      row.fetch('conditions', {}).fetch('groups', []).flat_map { |group| group.fetch('items') }
  end

  # Conservative publication guard: ties with disjoint conjunctions or disjoint
  # validity are safe; every other possible overlap must be explicitly resolved.
  def conflicts(rows)
    rows.reject { |row| row['enabled'] == false }.combination(2).filter_map do |left, right|
      next unless left['precedence'] == right['precedence']
      next if left['valid_until'] && right['valid_from'] && Time.iso8601(left['valid_until']) <= Time.iso8601(right['valid_from'])
      next if right['valid_until'] && left['valid_from'] && Time.iso8601(right['valid_until']) <= Time.iso8601(left['valid_from'])

      l = mandatory_equalities(left)
      r = mandatory_equalities(right)
      next if (l.keys & r.keys).any? { |field| l[field] != r[field] }

      [left['key'], right['key']]
    end
  end

  def mandatory_equalities(row)
    result = {}
    row['match'].each { |field, value| add_equality(result, field, value) }
    root = row['conditions']
    return result unless root && root['operator'] == 'all'

    root['groups'].select { |group| group['operator'] == 'all' }.flat_map { |group| group['items'] }.each do |item|
      add_equality(result, item['field'], item['value']) if item['operator'] == 'eq'
    end
    result
  end

  def add_equality(result, field, value)
    return if field == 'label_id'

    if field == 'form_value'
      result["form_value:#{value['key']}"] = value['value']
    else
      result[field] = value
    end
  end

  def equal?(actual, expected)
    return false unless available?(actual, expected)
    return actual[expected['key']] == expected['value'] if actual.is_a?(Hash) && expected.is_a?(Hash)

    actual.is_a?(Array) ? actual.include?(expected) : actual == expected
  end

  def available?(actual, expected)
    !actual.nil? && (!expected.is_a?(Hash) || (actual.is_a?(Hash) && actual.key?(expected['key'])))
  end

  def combine(operator, values)
    operator == 'all' ? values.all? : values.any?
  end

  def exact!(value, fields)
    JrcServiceDesk::OperationalRuleContract.fields!(value, fields)
  end

  def operator!(value)
    raise ArgumentError, 'Explicit AND/OR required' unless %w[all any].include?(value)
  end
end
