# frozen_string_literal: true

class JrcServiceDesk::TicketPermissions
  CAPABILITIES = %i[customer_publish technical_notes tasks_view tasks_manage approvals_view approvals_request].freeze

  def initialize(context, ticket, policy)
    @context = context
    @ticket = ticket
    @policy = policy
  end

  def call
    native.merge(operational).merge(snapshot_permissions).merge(
      lifecycle_inspect: JrcServiceDesk::LifecycleActionPolicy.new(@context, @ticket).inspect?,
      change_work_status: JrcServiceDesk::WorkStatusPolicy.new(@context, @ticket).change_work_status?,
      transition: false, pause: false, resolve: false, reopen: false
    )
  end

  private

  def snapshot_permissions
    snapshot = JrcServiceDesk::SlaSnapshot.new(account: @ticket.account, unit: @ticket.unit, ticket: @ticket)
    policy = JrcServiceDesk::SlaSnapshotPolicy.new(@context, snapshot)
    { record_sla_snapshot: policy.create?, view_contract_conditions: policy.show? }
  end

  def native
    { show: true, update: @policy.update?, change_priority: @policy.change_priority?, assign: @policy.assign?, transfer: @policy.transfer?,
      view_notes: @policy.view_notes?, view_history: @policy.view_history?, view_conversations: @policy.view_conversations?,
      view_sla: @policy.view_sla?, view_customer: @policy.view_customer?, add_note: @policy.add_note?, link_conversation: @policy.link_conversation? }
  end

  def operational
    context = JrcServiceDesk::OperationalContext.new(@context)
    CAPABILITIES.index_with { |key| context.capability?(key) }
  end
end
