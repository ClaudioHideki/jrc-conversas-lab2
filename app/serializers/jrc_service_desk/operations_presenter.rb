# frozen_string_literal: true

class JrcServiceDesk::OperationsPresenter
  def initialize(context:)
    @context = context
  end

  def call(kind, row)
    method = { 'tasks' => :task_payload, 'approvals' => :approval_payload, 'incidents' => :incident_payload,
               'problems' => :incident_payload, 'ola' => :ola_payload }.fetch(kind)
    send(method, row)
  end

  private

  def ticket_identity(row)
    { id: row.id.to_s, account_id: row.account_id.to_s, unit_id: row.unit_id.to_s, ticket_id: row.ticket_id.to_s }
  end

  def task_payload(row)
    Pundit.authorize(@context.to_h, row, :show?)
    ticket_identity(row).merge(task_details(row)).merge(task_progression(row)).merge(
      permissions: { show: true, update: ::JrcServiceDesk::TicketTaskPolicy.new(@context.to_h, row).update? }
    )
  end

  def task_details(row)
    { title: row.title, description: row.description, visibility: row.visibility, audience_team_id: row.audience_team_id&.to_s,
      status: row.status, priority: row.priority, due_at: row.due_at&.iso8601(6), completed_at: row.completed_at&.iso8601(6),
      checklist: row.checklist, assignee_account_user_id: row.assignee_membership&.account_user_id&.to_s, lock_version: row.lock_version }
  end

  def task_progression(row)
    { parent_task_id: row.parent_task_id&.to_s, completion_policy: row.completion_policy,
      pending_children: row.subtasks.where.not(status: %w[completed cancelled]).count }
  end

  def approval_payload(row)
    policy = ::JrcServiceDesk::TicketApprovalPolicy.new(@context.to_h, row)
    raise Pundit::NotAuthorizedError unless policy.show?

    ticket_identity(row).merge(approval_target(row)).merge(
      title: row.title, description: row.description, status: row.status, comment: row.comment,
      due_at: row.due_at&.iso8601(6), decided_at: row.decided_at&.iso8601(6), lock_version: row.lock_version, history: row.history,
      permissions: { show: true, decide: policy.decide?, escalate: policy.escalate? }
    )
  end

  def approval_target(row)
    { approver_account_user_id: row.approver_membership&.account_user_id&.to_s,
      approver_team_id: row.approver_team_id&.to_s, approver_role: row.approver_role,
      approver_custom_role_id: row.approver_custom_role_id&.to_s }
  end

  def incident_payload(row)
    Pundit.authorize(@context.to_h, row, :show?)
    visible_tickets = Pundit.policy_scope!(@context.to_h, ::JrcServiceDesk::Ticket).where(incident_id: row.id)
    incident_details(row).merge(
      primary_ticket_id: visible_tickets.exists?(id: row.primary_ticket_id) ? row.primary_ticket_id&.to_s : nil,
      ticket_ids: visible_tickets.pluck(:id).map(&:to_s)
    )
  end

  def incident_details(row)
    { id: row.id.to_s, account_id: row.account_id.to_s, unit_id: row.unit_id.to_s, lock_version: row.lock_version,
      resource_kind: row.resource_kind, owner_account_user_id: row.owner_membership&.account_user_id&.to_s,
      permissions: { show: true, update: JrcServiceDesk::IncidentPolicy.new(@context.to_h, row).update? } }
      .merge(row.slice(:title, :description, :severity, :status, :impact, :cause, :workaround, :resolution).symbolize_keys)
  end

  def ola_payload(row)
    JrcServiceDesk::ClockProjection.new(row).call.merge(queue_id: row.queue_id.to_s, ended_at: row.ended_at&.iso8601(6),
                                                        policy_revision: row.policy_revision)
  end
end
