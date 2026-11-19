# frozen_string_literal: true

# Reuse the native field contract, without reading Service Desk records or inheriting its permissions.
class JrcContactCenter::AcwFormDefinition
  MAX_BYTES = 262_144
  MAX_OPTIONS = 100

  class Invalid < JrcContactCenter::OperationError
    attr_reader :fields

    def initialize(fields = ['definition'])
      @fields = fields
      super('invalid_acw_form_definition')
    end
  end

  def initialize(value)
    @value = value
  end

  def call
    valid = @value.is_a?(Hash) && @value.keys == ['fields'] && @value.to_json.bytesize <= MAX_BYTES
    raise Invalid unless valid

    validated_fields.each_with_index { |field, index| validate_field!(field, index) }
    @value.deep_dup
  end

  private

  def validated_fields
    fields = @value.fetch('fields')
    schema = JrcServiceDesk::CatalogueFields.new(fields)
    raise Invalid, ['fields'] unless schema.valid? && !schema.duplicate_keys? && fields.any?

    fields
  end

  def validate_field!(field, index)
    label = field.fetch('label')
    raise Invalid, ["fields.#{index}.label"] if label.strip.empty? || label.include?("\0")
    return validate_options!(field, index) if field.fetch('type') == 'select'
    return unless field.key?('options')

    raise Invalid, ["fields.#{index}.options"]
  end

  def validate_options!(field, index)
    values = field.fetch('options')
    valid = values.length <= MAX_OPTIONS && values.uniq.length == values.length && values.none? { |value| value.strip.empty? || value.include?("\0") }
    raise Invalid, ["fields.#{index}.options"] unless valid
  end
end
