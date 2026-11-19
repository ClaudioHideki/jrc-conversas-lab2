# frozen_string_literal: true

# The shared value validator performs no Service Desk reads or authorization.
# This class validates only a caller-authorized immutable ACW definition and answers.
class JrcContactCenter::AcwFormAnswers
  MAX_BYTES = 262_144

  class Invalid < JrcContactCenter::OperationError
    def initialize
      super('invalid_acw_form_answers')
    end
  end

  def initialize(definition:, answers:)
    @fields = JrcContactCenter::AcwFormDefinition.new(definition).call.fetch('fields')
    @answers = answers
  end

  def call(complete:)
    validate_envelope!(complete)

    fields = complete ? @fields : @fields.map { |field| field.merge('required' => false) }
    JrcServiceDesk::CatalogueAnswers.new(fields).validate!(@answers)
    validate_strings!
    validate_required_text! if complete
    @answers.deep_dup
  rescue ArgumentError
    raise Invalid
  end

  private

  def validate_envelope!(complete)
    valid = [true, false].include?(complete) && @answers.is_a?(Hash) && @answers.to_json.bytesize <= MAX_BYTES
    raise Invalid unless valid
  end

  def validate_strings!
    invalid = @answers.values.any? { |value| value.is_a?(String) && value.include?("\0") }
    raise Invalid if invalid
  end

  def validate_required_text!
    missing = @fields.any? do |field|
      field['required'] && field['type'] == 'text' && @answers[field['key']].strip.empty?
    end
    raise Invalid if missing
  end
end
