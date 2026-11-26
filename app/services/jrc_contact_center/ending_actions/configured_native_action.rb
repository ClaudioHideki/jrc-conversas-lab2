# frozen_string_literal: true

# Configuration authority only. The original operator is independently checked
# again by the native executor; saving never creates a Lead, Activity or Task.
class JrcContactCenter::EndingActions::ConfiguredNativeAction
  def self.crm_available?(member)
    current = JrcOperations::Access.refresh(member)
    # Preserve ContactLeadService's existing native membership condition, in
    # addition to the CRM controller permission. Neither implies the other.
    JrcOperations::Access.crm?(current) && (current.administrator? || current.crm_enabled?)
  end

  def initialize(account:, member:, source_scope: nil)
    @account = account
    @source_scope = source_scope
    @member = account.account_users.find_by!(id: member.id, user_id: member.user_id)
  end

  def call(value, active:)
    action = JrcContactCenter::EndingActions::DestinationOperationDefinition.new.call(value)
    case action.fetch('kind')
    when 'project_task'
      project_parameters(action, active)
    when 'crm'
      raise Pundit::NotAuthorizedError unless self.class.crm_available?(@member)

      action
    when 'service_desk'
      service_desk_parameters(action, active)
    else
      raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable'
    end
  end

  private

  def service_desk_parameters(action, active)
    parameters = action.fetch('parameters')
    raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable' if parameters.key?('operation')
    raise JrcContactCenter::OperationError, 'ending_service_desk_mapping_required' unless @source_scope.is_a?(Hash)

    context = { account: @account, account_user: @member, user: @member.user }
    validator = JrcContactCenter::EndingActions::ServiceDeskRuleParameters.new(user_context: context, source_scope: @source_scope)
    checked = active ? validator.call(parameters) : validator.authorize_reference!(parameters)
    action.merge('parameters' => checked)
  end

  def project_parameters(action, active)
    validator = JrcContactCenter::EndingActions::ProjectTaskParameters.new(member: @member)
    parameters = action.fetch('parameters')
    checked = active ? validator.call(parameters) : validator.authorize_reference!(parameters)
    action.merge('parameters' => checked)
  end
end
