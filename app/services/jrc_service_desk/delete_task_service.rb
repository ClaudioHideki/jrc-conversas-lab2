# frozen_string_literal: true

class JrcServiceDesk::DeleteTaskService < JrcServiceDesk::BaseService
  def call(ticket_id:, task_id:, expected_lock_version:, reason:)
    reason = JrcServiceDesk::RecordWithdrawal.reason(reason)
    with_ticket(ticket_id, :show?) do |ticket|
      row = ticket.ticket_tasks.lock.find(JrcServiceDesk::Input.id(task_id))
      authorize!(row, :destroy?)
      verify_version!(row, expected_lock_version)
      children = JrcServiceDesk::RecordWithdrawal.excluding(row.subtasks, :task)
      if children.exists?
        raise JrcServiceDesk::DeletionBlockedError, 'Exclua as subtarefas antes de excluir esta tarefa.'
      end

      row.touch
      JrcServiceDesk::TicketEvent.create!(
        account: context.account, unit: ticket.unit, ticket: ticket, actor_membership: actor_membership,
        event_type: 'task_deleted', visibility: row.visibility, audience_team_id: row.audience_team_id,
        data: { 'task_id' => row.id, 'reason' => reason }
      )
      row
    end
  end
end
