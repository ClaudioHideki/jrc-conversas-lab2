# frozen_string_literal: true

class JrcServiceDesk::EscalateApprovalService < JrcServiceDesk::BaseService
  def call(ticket_id:, approval_id:, attributes:, expected_lock_version:)
    values = JrcServiceDesk::Input.attributes(attributes, %w[reason due_at] + JrcServiceDesk::ApprovalTarget::FIELDS)
    reason = text(values.fetch('reason'))
    raise ArgumentError, 'Escalation reason required' unless reason.strip.size.between?(1, 4000)

    with_ticket(ticket_id, :show?) do |ticket|
      row = ticket.ticket_approvals.lock.find(JrcServiceDesk::Input.id(approval_id))
      authorize!(row, :escalate?)
      verify_version!(row, expected_lock_version)
      escalate!(ticket, row, values, reason)
      append_event!(ticket, 'approval_escalated', 'approval_id' => row.id, 'history_index' => row.history.size - 1)
      row
    end
  end

  private

  def escalate!(ticket, row, values, reason)
    before = target_snapshot(row)
    target = JrcServiceDesk::ApprovalTarget.new(context: context, unit: ticket.unit).attributes(values)
    row.authorized_escalation = true
    row.assign_attributes(target)
    row.due_at = Time.iso8601(values['due_at']) if values['due_at']
    raise ArgumentError, 'Approval target or deadline must change' unless row.changed?

    entry = { 'action' => 'escalation', 'actor_membership_id' => actor_membership.id, 'reason' => reason,
              'occurred_at' => Time.current.iso8601(6), 'from' => JrcServiceDesk::CanonicalJson.normalize(before),
              'to' => JrcServiceDesk::CanonicalJson.normalize(target_snapshot(row)) }
    row.update!(escalated_by_membership: actor_membership, history: row.history + [entry])
  end

  def target_snapshot(row)
    attributes = row.slice(:approver_membership_id, :approver_team_id, :approver_role, :approver_custom_role_id, :due_at)
    attributes['due_at'] = attributes['due_at']&.iso8601(6)
    attributes
  end
end
