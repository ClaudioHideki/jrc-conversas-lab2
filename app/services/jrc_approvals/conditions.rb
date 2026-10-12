require 'bigdecimal'
require 'time'

class JrcApprovals::Conditions
  OPERATORS = {
    'integer' => %w[eq neq lt lte gt gte between in], 'decimal' => %w[eq neq lt lte gt gte between in],
    'money' => %w[eq neq lt lte gt gte between in], 'datetime' => %w[eq neq lt lte gt gte between in],
    'string' => %w[eq neq contains in], 'boolean' => %w[eq neq]
  }.freeze

  def self.value!(type, value)
    case type
    when 'integer'
      return value if value.is_a?(Integer)
    when 'decimal'
      return BigDecimal(value).to_r if value.is_a?(String) && value.match?(/\A-?\d+(?:\.\d+)?\z/) && value.size <= 100
    when 'string'
      return value if value.is_a?(String) && value.bytesize <= 4096
    when 'boolean'
      return value if [true, false].include?(value)
    when 'money'
      if value.is_a?(Hash) && value.keys.sort == %w[amount_cents currency] && value['amount_cents'].is_a?(Integer) &&
         value['currency'].is_a?(String) && value['currency'].match?(/\A[A-Z]{3}\z/)
        return [value['currency'], value['amount_cents']]
      end
    when 'datetime'
      return Time.iso8601(value) if value.is_a?(String) && value.match?(/(?:Z|[+-]\d{2}:\d{2})\z/)
    end
    raise JrcApprovals::Error, 'INVALID_TYPED_VALUE'
  rescue ArgumentError
    raise JrcApprovals::Error, 'INVALID_TYPED_VALUE'
  end

  def initialize(schema)
    @schema = schema
  end

  def validate!(node, depth = 0, budget = [0])
    budget[0] += 1
    reject! unless node.is_a?(Hash) && depth <= 4 && budget[0] <= 32
    if node.keys == ['const']
      reject! unless [true, false].include?(node['const'])
    elsif node.keys == ['all'] || node.keys == ['any']
      children = node.values.first
      reject! unless children.is_a?(Array) && children.size.between?(1, 8)
      children.each { |child| validate!(child, depth + 1, budget) }
    else
      reject! unless node.keys.sort == %w[field op value] && @schema.key?(node['field'])
      type = @schema.fetch(node['field'])
      reject! unless OPERATORS.fetch(type).include?(node['op'])
      values = %w[in between].include?(node['op']) ? node['value'] : [node['value']]
      reject! unless values.is_a?(Array) && values.size.between?(1, 32)
      reject! if node['op'] == 'between' && values.size != 2
      values.each { |value| self.class.value!(type, value) }
      reject! if type == 'money' && values.map { |v| v['currency'] }.uniq.size != 1
      reject! if node['op'] == 'between' && comparable(type, values[0], values[1]) > 0
    end
    true
  end

  def match?(node, values)
    validate!(node)
    evaluate(node, values)
  end

  private

  def evaluate(node, values)
    return node['const'] if node.key?('const')
    return node['all'].all? { |child| evaluate(child, values) } if node.key?('all')
    return node['any'].any? { |child| evaluate(child, values) } if node.key?('any')

    type = @schema.fetch(node['field'])
    actual = values.fetch(node['field']) { raise JrcApprovals::Error, 'MISSING_CONTEXT' }
    expected = node['value']
    case node['op']
    when 'in' then expected.any? { |v| comparable(type, actual, v).zero? }
    when 'between' then comparable(type, actual, expected[0]) >= 0 && comparable(type, actual, expected[1]) <= 0
    when 'contains' then self.class.value!(type, actual).include?(expected)
    else
      comparison = comparable(type, actual, expected)
      { 'eq' => comparison.zero?, 'neq' => !comparison.zero?, 'lt' => comparison < 0,
        'lte' => comparison <= 0, 'gt' => comparison > 0, 'gte' => comparison >= 0 }.fetch(node['op'])
    end
  end

  def comparable(type, left, right)
    a = self.class.value!(type, left)
    b = self.class.value!(type, right)
    if type == 'money'
      raise JrcApprovals::Error, 'INCOMPATIBLE_CURRENCY' unless a[0] == b[0]

      a, b = a[1], b[1]
    end
    return a == b ? 0 : 1 if type == 'boolean'

    a <=> b
  end

  def reject!
    raise JrcApprovals::Error, 'INVALID_CONDITION'
  end
end
