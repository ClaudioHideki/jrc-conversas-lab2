# frozen_string_literal: true

class JrcServiceDesk::DecideApprovalService < JrcServiceDesk::BaseService
  def call(ticket_id:, approval_id:, attributes:, expected_lock_version:)
    values = JrcServiceDesk::Input.attributes(attributes, %w[status comment])
    raise ArgumentError, 'Approval decision required' unless %w[approved rejected returned].include?(values['status'])

    with_ticket(ticket_id, :show?) do |ticket|
      row = ticket.ticket_approvals.lock.find(JrcServiceDesk::Input.id(approval_id))
      authorize!(row, :decide?)
      next verify_replay!(row, values) if row.status != 'pending'

      verify_version!(row, expected_lock_version)
      entry = { 'action' => 'decision', 'actor_membership_id' => actor_membership.id,
                'status' => values['status'], 'comment' => values['comment'], 'occurred_at' => Time.current.iso8601(6) }
      row.update!(status: values['status'], comment: values['comment'], decided_at: Time.current,
                  decided_by_membership: actor_membership, history: row.history + [entry])
      changes = JrcServiceDesk::RecordedChanges.call(row.saved_changes.except('updated_at', 'lock_version'))
      append_event!(ticket, 'approval_decided', 'approval_id' => row.id, 'changes' => changes)
      row
    end
  end

  private

  def verify_replay!(row, values)
    raise JrcServiceDesk::IdempotencyConflict unless row.status == values['status'] && row.comment == values['comment']

    row
  end
end
