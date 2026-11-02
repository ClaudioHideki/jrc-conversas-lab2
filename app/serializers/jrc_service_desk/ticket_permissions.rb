# frozen_string_literal: true

class JrcServiceDesk::TicketPermissions
  CAPABILITIES = %i[customer_publish technical_notes tasks_view tasks_manage approvals_view approvals_request].freeze

  def initialize(context, ticket, policy, read_projection: nil)
    @context = context
    @ticket = ticket
    @policy = policy
    @read_projection = read_projection
  end

  def call
    native.merge(operational).merge(snapshot_permissions).merge(
      lifecycle_inspect: policy_for(@ticket, JrcServiceDesk::LifecycleActionPolicy).inspect?,
      change_work_status: policy_for(@ticket, JrcServiceDesk::WorkStatusPolicy).change_work_status?,
      transition: false, pause: false, resolve: false, reopen: false
    )
  end

  private

  def snapshot_permissions
    snapshot = JrcServiceDesk::SlaSnapshot.new(account: @ticket.account, unit: @ticket.unit, ticket: @ticket)
    policy = policy_for(snapshot, JrcServiceDesk::SlaSnapshotPolicy)
    { record_sla_snapshot: policy.create?, view_contract_conditions: policy.show? }
  end

  def native
    { show: true, destroy: @policy.destroy?, update: @policy.update?, change_priority: @policy.change_priority?, assign: @policy.assign?, transfer: @policy.transfer?,
      view_notes: @policy.view_notes?, view_history: @policy.view_history?, view_conversations: @policy.view_conversations?,
      view_sla: @policy.view_sla?, view_customer: @policy.view_customer?, add_note: @policy.add_note?, link_conversation: @policy.link_conversation? }
  end

  def operational
    context = @read_projection ? @read_projection.context : JrcServiceDesk::OperationalContext.new(@context)
    CAPABILITIES.index_with { |key| context.capability?(key) && @policy.scoped_permission?(key) }
  end

  def policy_for(record, policy_class)
    @read_projection ? @read_projection.policy(record, policy_class: policy_class) : policy_class.new(@context, record)
  end
end
