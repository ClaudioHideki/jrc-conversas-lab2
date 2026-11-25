# frozen_string_literal: true

# Structure only. Contact, company, user, unit, timestamps and audit identity are
# resolved by the original-actor command, never accepted from rule parameters.
class JrcContactCenter::EndingActions::CrmActivityDefinition
  def call(value)
    invalid! unless value.is_a?(Hash)

    row = value.deep_stringify_keys
    invalid! unless shape?(row)
    invalid! unless text?(row['title'], 240)
    invalid! if row.key?('description') && !description?(row['description'])
    invalid! unless activity_type?(row['activity_type'])

    row.deep_dup
  end

  private

  def shape?(row)
    (row.keys - %w[activity_type description title]).empty? && (%w[activity_type title] - row.keys).empty?
  end

  def activity_type?(value)
    value.is_a?(String) && JrcCrm::Activity::ACTIVITY_TYPES.include?(value)
  end

  def description?(value)
    value.nil? || (value.is_a?(String) && value.valid_encoding? && value.exclude?("\u0000") && value.length <= 6000)
  end

  def text?(value, maximum)
    value.is_a?(String) && value.valid_encoding? && value.exclude?("\u0000") &&
      value.length <= maximum && value.strip.present? && value == value.strip
  end

  def invalid!
    raise JrcContactCenter::OperationError, 'invalid_ending_crm_activity_parameters'
  end
end
