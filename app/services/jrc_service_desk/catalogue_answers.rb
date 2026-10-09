# frozen_string_literal: true

class JrcServiceDesk::CatalogueAnswers
  def initialize(fields)
    @fields = fields
  end

  def validate!(answers)
    raise ArgumentError, 'Service answers must be an object' unless answers.is_a?(Hash)
    raise ArgumentError, 'Unknown service field' if (answers.keys - @fields.map { |field| field.fetch('key') }).any?

    @fields.each { |field| validate_field!(field, answers[field['key']]) }
    true
  end

  private

  def validate_field!(field, value)
    raise ArgumentError, 'Required service field missing' if field['required'] && (value.nil? || value == '')
    return if value.nil?
    raise ArgumentError, 'Invalid service field' unless valid_value?(field, value)
  end

  def valid_value?(field, value)
    case field['type']
    when 'text' then value.is_a?(String) && value.size <= 4000
    when 'integer' then value.is_a?(Integer) && value.abs <= ((2**53) - 1)
    when 'boolean' then [true, false].include?(value)
    when 'select' then field.fetch('options').include?(value)
    end
  end
end
