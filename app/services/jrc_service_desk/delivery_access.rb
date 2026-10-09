# frozen_string_literal: true

class JrcServiceDesk::DeliveryAccess
  def initialize(context)
    @context = context
  end

  def allowed?(row)
    origin = row.ticket_note || row.ticket_event
    origin && Pundit.policy!(@context.to_h, origin).show? && task_allowed?(origin) && conversation_allowed?(row)
  end

  private

  def task_allowed?(origin)
    return true unless origin.is_a?(JrcServiceDesk::TicketEvent) && %w[task_created task_updated].include?(origin.event_type)

    task = JrcServiceDesk::TicketTask.find_by(id: origin.data['task_id'], account_id: origin.account_id,
                                              unit_id: origin.unit_id, ticket_id: origin.ticket_id)
    task && Pundit.policy!(@context.to_h, task).show?
  end

  def conversation_allowed?(row)
    return true unless row.conversation

    link = row.ticket.ticket_conversations.find_by(conversation_id: row.conversation_id)
    link && Pundit.policy!(@context.to_h, link).show?
  end
end
