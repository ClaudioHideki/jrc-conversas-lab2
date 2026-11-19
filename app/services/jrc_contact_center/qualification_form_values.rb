# frozen_string_literal: true

# Preserves typed drafts per immutable rule/version; only explicit completion requires all selected fields.
class JrcContactCenter::QualificationFormValues
  def initialize(account:, snapshot:)
    @account = account
    @pins = snapshot.fetch('bindings').index_by { |row| row.fetch('rule_id') }
  end

  def merge(previous, input)
    validate_map!(previous)
    return previous.deep_dup if input == :unchanged

    validate_map!(input)
    result = previous.deep_dup
    input.each do |key, values|
      valid = values.is_a?(Hash) && values.keys.all?(String)
      raise JrcContactCenter::AcwFormAnswers::Invalid unless valid

      merged = result.fetch(key, {}).merge(values)
      result[key] = JrcContactCenter::AcwFormAnswers.new(definition: definition(key), answers: merged).call(complete: false)
    end
    validate_map!(result)
    result
  end

  def complete!(binding, answers)
    return unless binding

    key = binding.fetch('rule_id')
    JrcContactCenter::AcwFormAnswers.new(definition: definition(key), answers: answers.fetch(key, {})).call(complete: true)
  end

  private

  def validate_map!(value)
    valid = value.is_a?(Hash) && value.keys.all?(String) && (value.keys - @pins.keys).empty? &&
            value.values.all?(Hash) &&
            value.to_json.bytesize <= JrcContactCenter::AcwFormAnswers::MAX_BYTES
    raise JrcContactCenter::AcwFormAnswers::Invalid unless valid
  end

  def definition(key)
    JrcContactCenter::AcwFormBindings.new(account: @account).resolve!(@pins.fetch(key)).fetch('definition')
  end
end
