# frozen_string_literal: true

# Internal native command only. Its future caller owns the original-actor
# transaction and its independent immutable receipt. No rule is activated here.
class JrcContactCenter::EndingActions::CrmActivityDestination
  def initialize(account:, member:)
    @account = account
    @member = JrcOperations::Access.refresh(member)
  end

  def call(origin:, parameters:, trigger_at:)
    raise JrcContactCenter::OperationError, 'ending_destination_requires_transaction' unless Account.connection.transaction_open?

    valid_trigger = trigger_at.is_a?(Time) || trigger_at.is_a?(ActiveSupport::TimeWithZone)
    raise JrcContactCenter::OperationError, 'ending_action_trigger_pending' unless valid_trigger

    attributes = JrcContactCenter::EndingActions::CrmActivityDefinition.new.call(parameters)
    ActiveRecord::Base.logger.silence(Logger::WARN) { create_for_original_lead(origin, attributes, trigger_at) }
  end

  private

  def create_for_original_lead(origin, attributes, trigger_at)
    result = JrcContactCenter::EndingActions::CrmLeadDestination.new(account: @account, member: @member).call(origin: origin)
    result.fetch(:lead).with_lock do
      reference = JrcContactCenter::EndingActions::OriginalCustomerReference.new(account: @account, member: @member, origin: origin).call
      scope = JrcDomainCommands::ResourceScope.new(account: @account, user: @member.user)
      lead = scope.authorize!(@account.jrc_crm_leads.find(result.fetch(:lead).id))
      raise JrcContactCenter::OperationError, 'ending_customer_reference_changed' unless lead.contact_id == reference.fetch(:contact_id)

      activity = build_activity(lead, attributes, trigger_at)
      persist_native!(activity)
      scope.authorize!(activity.reload)
    end
  end

  def build_activity(lead, attributes, trigger_at)
    # Corporate identity comes only from the already visible native Lead.
    # This copies no coverage/grant and never accepts an arbitrary unit or user.
    @account.jrc_crm_activities.new(
      attributes.merge(
        'lead' => lead, 'user' => @member.user, 'contact_id' => lead.contact_id, 'company_id' => lead.company_id,
        'business_unit_id' => lead.business_unit_id, 'status' => 'completed', 'completed_at' => trigger_at, 'due_at' => trigger_at
      )
    )
  end

  def persist_native!(activity)
    result = JrcCrm::ActivityDispatchService.new(activity: activity, actor: @member.user).call
    raise JrcContactCenter::OperationError, 'ending_crm_native_activity_invalid' unless result.fetch(:success)

    events = JrcCrm::AuditEvent.where(
      account: @account, resource_type: activity.class.name, resource_id: activity.id,
      event_type: 'activity_created', actor_type: @member.user.class.name, actor_id: @member.user_id
    )
    raise JrcContactCenter::OperationError, 'ending_crm_native_audit_missing' unless events.exists?
  end
end
