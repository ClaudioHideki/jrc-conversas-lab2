require 'date'
require 'uri'

class JrcFlowEffects::Resources
  TYPES = { 'text' => 'string', 'number' => 'number', 'currency' => 'number', 'percent' => 'number',
            'link' => 'url', 'date' => 'date', 'list' => 'enum', 'checkbox' => 'boolean' }.freeze

  def self.catalogue(account)
    labels = account.labels.limit(1001).to_a
    definitions = account.custom_attribute_definitions.where(attribute_model: :conversation_attribute).limit(1001).to_a
    raise ArgumentError, 'catalogue_bound' if labels.size > 1000 || definitions.size > 1000

    labels.filter_map { |row| metadata(row, 'tag') } + definitions.filter_map { |row| metadata(row, 'attribute') }
  end

  def self.metadata(row, operation)
    data = resource_data(row, operation)
    return unless data
    return unless data[:name].is_a?(String) && data[:name].length.between?(1, 120)

    data.merge(revision: Digest::SHA256.hexdigest([data, row.updated_at.utc.iso8601(6)].to_json))
  end

  def self.resource_data(row, operation)
    if operation == 'tag'
      { id: row.id, kind: 'LABEL', name: row.title, key: "label_#{row.id}", definition: nil }
    else
      definition = definition(row)
      return unless definition

      { id: row.id, kind: 'ATTRIBUTE', name: row.attribute_display_name, key: row.attribute_key, definition: definition }
    end
  end

  def self.definition(row)
    return if row.regex_pattern.present?

    type = TYPES[row.attribute_display_type]
    return unless type && /\A[a-zA-Z_][a-zA-Z0-9_-]{0,99}\z/.match?(row.attribute_key)

    values = type == 'enum' ? Array(row.attribute_values) : []
    return unless valid_values?(values)

    { valueType: type, maxLength: 4096, allowedValues: values }
  end

  def self.valid_values?(values)
    values.size <= 100 && values.uniq.size == values.size &&
      values.all? { |value| value.is_a?(String) && value.bytesize.between?(1, 120) }
  end

  def self.typed_value!(definition, value)
    bounded = !value.is_a?(String) || value.bytesize <= definition[:maxLength]
    raise ArgumentError, 'value' unless bounded && valid_type?(definition, value)

    value
  rescue URI::InvalidURIError, Date::Error
    raise ArgumentError, 'value'
  end

  def self.valid_type?(definition, value)
    case definition[:valueType]
    when 'boolean' then [true, false].include?(value)
    when 'number' then finite_number?(value)
    when 'enum' then definition[:allowedValues].include?(value)
    when 'date' then valid_date?(value)
    when 'url' then valid_url?(value)
    else value.is_a?(String)
    end
  end

  def self.finite_number?(value)
    value.is_a?(Numeric) && value.finite?
  end

  def self.valid_date?(value)
    value.is_a?(String) && /\A\d{4}-\d{2}-\d{2}\z/.match?(value) && Date.iso8601(value).iso8601 == value
  end

  def self.valid_url?(value)
    uri = value.is_a?(String) ? URI.parse(value) : nil
    uri && %w[http https].include?(uri.scheme) && uri.host.present? && uri.userinfo.nil?
  end
end
