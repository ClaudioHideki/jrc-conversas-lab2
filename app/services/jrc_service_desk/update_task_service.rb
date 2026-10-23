# frozen_string_literal: true

class JrcServiceDesk::UpdateTaskService < JrcServiceDesk::BaseService
  def call(ticket_id:, task_id:, attributes:, expected_lock_version:)
    values = JrcServiceDesk::Input.attributes(attributes, %w[title description status checklist due_at priority assignee_account_user_id])
    raise ArgumentError, 'Task fields required' if values.empty?

    with_ticket(ticket_id, :show?) do |ticket|
      row = ticket.ticket_tasks.lock.find(JrcServiceDesk::Input.id(task_id))
      authorize!(row, :update?)
      verify_version!(row, expected_lock_version)
      if %w[completed cancelled].include?(row.status) && (values.keys - %w[title description]).any?
        raise ArgumentError, 'Tarefas concluídas ou canceladas permitem somente corrigir título e descrição'
      end

      assign_task_changes(row, ticket, values)
      next row unless row.changed?

      row.save!
      record_update(ticket, row)
      if row.saved_change_to_status? && row.status == 'completed'
        JrcServiceDesk::TaskProgression.new(context: context, ticket: ticket, task: row).call
      end
      row
    end
  end

  private

  def assign_task_changes(row, ticket, values)
    row.assign_attributes(values.except('assignee_account_user_id', 'due_at'))
    row.due_at = values['due_at'] && Time.iso8601(values['due_at']) if values.key?('due_at')
    row.assignee_membership = assignee(values['assignee_account_user_id'], ticket.unit) if values.key?('assignee_account_user_id')
    row.completed_at = Time.current if row.will_save_change_to_status? && row.status == 'completed'
  end

  def record_update(ticket, row)
    changes = JrcServiceDesk::RecordedChanges.call(row.saved_changes.except('updated_at', 'lock_version'))
    JrcServiceDesk::TicketEvent.create!(
      account: context.account, unit: ticket.unit, ticket: ticket, actor_membership: actor_membership,
      event_type: 'task_updated', visibility: row.visibility, audience_team_id: row.audience_team_id,
      data: { 'task_id' => row.id, 'changes' => changes }
    )
  end
end
