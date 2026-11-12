# Native contact JSON fields keep their existing storage. Only configured contact
# attributes are offered; CSV columns never grant access to model/tenant fields.
class JrcCustomers::ImportContactFields
  PREFIX = 'custom_attributes.'.freeze

  def initialize(account:)
    @account = account
  end

  def keys
    definitions.pluck(:attribute_key)
  end

  def apply!(values)
    additional = values.extract!('city', 'company_name')
    values['additional_attributes'] = additional if additional.any?
    custom = values.keys.grep(/\Acustom_attributes\./).to_h do |field|
      definition = definitions.find_by!(attribute_key: field.delete_prefix(PREFIX))
      [definition.attribute_key, typed_value!(definition, values.delete(field))]
    end
    values['custom_attributes'] = custom if custom.any?
  rescue ActiveRecord::RecordNotFound
    raise JrcCustomers::ImportIssue.new('Choose only configured contact attributes', field: 'custom_attributes', code: 'UNKNOWN_ATTRIBUTE')
  end

  def merge!(contact, values)
    values['custom_attributes'] = (contact.custom_attributes || {}).merge(values['custom_attributes']) if values['custom_attributes']
    return unless values['additional_attributes']

    values['additional_attributes'] = (contact.additional_attributes || {}).merge(values['additional_attributes'])
    company = contact.master_company
    values['additional_attributes']['company_name'] = company.name if company
  end

  private

  def definitions
    @account.custom_attribute_definitions.contact_attribute
  end

  def typed_value!(definition, raw)
    value = cast_value(definition.attribute_display_type, raw)
    type = JrcFlowEffects::Resources::TYPES.fetch(definition.attribute_display_type)
    rules = { valueType: type, maxLength: 65_536, allowedValues: Array(definition.attribute_values) }
    JrcFlowEffects::Resources.typed_value!(rules, value)
    raise ArgumentError if definition.regex_pattern.present? && !Regexp.new(definition.regex_pattern, timeout: 0.1).match?(raw)

    value
  rescue ArgumentError, RegexpError
    raise JrcCustomers::ImportIssue.new('Review the configured attribute type, values and format', field: "#{PREFIX}#{definition.attribute_key}")
  end

  def cast_value(type, raw)
    return Float(raw) if %w[number currency percent].include?(type)
    return raw unless type == 'checkbox'

    raise ArgumentError unless %w[true false].include?(raw)

    raw == 'true'
  end
end
