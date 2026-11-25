# frozen_string_literal: true

# Structure only. This does not activate a rule, grant access, create a native
# record or replace per-attempt original-agent/destination authorization.
# The new kinds stay unpublished until the native adapter and receipt gates pass.
class JrcContactCenter::EndingActions::ActionDefinition
  def call(value)
    input = JrcServiceDesk::Input.attributes(value, %w[kind parameters])
    invalid! unless input.keys.sort == %w[kind parameters] && input['kind'].is_a?(String)

    { 'kind' => input.fetch('kind'), 'parameters' => parameters(input.fetch('kind'), input.fetch('parameters')) }
  rescue ArgumentError
    invalid!
  end

  private

  def parameters(kind, value)
    case kind
    when 'project_task'
      JrcContactCenter::EndingActions::TaskDefinition.new.call(value)
    when 'crm'
      # The native contact/lead workflow owns contact identity, owner and reuse.
      # No caller-supplied customer, account, unit, actor or owner is accepted.
      invalid! unless value.is_a?(Hash) && value.empty?

      {}
    when 'service_desk'
      JrcContactCenter::EndingActions::ServiceDeskDestinationDefinition.new.call(value)
    else
      raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable'
    end
  end

  def invalid!
    raise JrcContactCenter::OperationError, 'invalid_ending_automation_definition'
  end
end
