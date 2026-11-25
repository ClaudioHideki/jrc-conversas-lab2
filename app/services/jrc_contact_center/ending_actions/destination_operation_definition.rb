# frozen_string_literal: true

# Structure only for an explicitly new rule schema. This does not select a
# caller, grant access, dispatch work or create an immutable execution receipt.
class JrcContactCenter::EndingActions::DestinationOperationDefinition
  def call(value)
    action = JrcServiceDesk::Input.attributes(value, %w[kind parameters])
    invalid! unless action.keys.sort == %w[kind parameters]

    parameters = action.fetch('parameters')
    return JrcContactCenter::EndingActions::ActionDefinition.new.call(action) unless explicit_operation?(parameters)

    { 'kind' => action.fetch('kind'), 'parameters' => operation!(action.fetch('kind'), parameters) }
  rescue ArgumentError
    invalid!
  end

  private

  def explicit_operation?(value)
    value.is_a?(Hash) && (value.key?('operation') || value.key?(:operation))
  end

  def operation!(kind, value)
    input = JrcServiceDesk::Input.attributes(value, %w[operation parameters])
    invalid! unless input.keys.sort == %w[operation parameters]

    validator = validator!(kind, input.fetch('operation'))
    { 'operation' => input.fetch('operation'), 'parameters' => validator.call(input.fetch('parameters')) }
  end

  def validator!(kind, operation)
    case [kind, operation]
    when %w[crm create_activity]
      JrcContactCenter::EndingActions::CrmActivityDefinition.new
    when %w[service_desk update_ticket]
      JrcContactCenter::EndingActions::ServiceDeskUpdateDefinition.new
    else
      raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable'
    end
  end

  def invalid!
    raise JrcContactCenter::OperationError, 'invalid_ending_automation_definition'
  end
end
