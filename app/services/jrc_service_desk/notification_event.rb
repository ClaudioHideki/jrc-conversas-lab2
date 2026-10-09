class JrcServiceDesk::NotificationEvent
  TYPES = %w[customer_interaction ticket_created ticket_assigned status_changed waiting_customer approval_requested approval_decided
             resolved closed reopened task_created task_updated task_completed].freeze
  DIRECT = {
    'ticket_created' => 'ticket_created', 'ticket_assigned' => 'ticket_assigned', 'ticket_claimed' => 'ticket_assigned',
    'approval_requested' => 'approval_requested', 'approval_decided' => 'approval_decided', 'task_created' => 'task_created'
  }.freeze
  LIFECYCLE = { 'resolve' => 'resolved', 'close' => 'closed', 'reopen' => 'reopened', 'resume' => 'status_changed',
                'work_status' => 'status_changed', 'cancel' => 'status_changed' }.freeze

  def self.type(source)
    return 'customer_interaction' if source.is_a?(JrcServiceDesk::TicketNote)
    return DIRECT[source.event_type] if DIRECT.key?(source.event_type)
    return lifecycle(source) if source.event_type == 'lifecycle_transitioned'
    return 'status_changed' if source.event_type == 'ticket_updated' && source.data.key?('status_id')
    return task_type(source) if source.event_type == 'task_updated'

    nil
  end

  def self.lifecycle(source)
    return LIFECYCLE[source.data['action']] unless source.data['action'] == 'pause'

    status = JrcServiceDesk::TicketStatus.find_by(account_id: source.account_id, unit_id: source.unit_id, id: source.data['to_status_id'])
    status&.phase == 'waiting' ? 'waiting_customer' : 'status_changed'
  end

  def self.task_type(source)
    changes = source.data.fetch('changes', {})
    changes['status']&.last == 'completed' ? 'task_completed' : 'task_updated'
  end

  def self.public_task(source)
    return unless type(source)&.start_with?('task_')

    task = source.ticket.ticket_tasks.find_by(id: source.data['task_id'])
    task if task&.visibility == 'customer'
  end

  def self.active?(source)
    event_type = type(source)
    return false unless event_type
    return false if event_type.start_with?('task_') && public_task(source).nil?

    %w[email whatsapp].any? { |channel| JrcServiceDesk::NotificationPolicySelector.call(source, channel)&.enabled? }
  end
end
