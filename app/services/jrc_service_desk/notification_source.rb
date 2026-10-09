class JrcServiceDesk::NotificationSource
  FIELDS = %w[body number title status priority queue assignee task_title task_status].freeze

  def initialize(record)
    @record = record
  end

  def type
    JrcServiceDesk::NotificationEvent.type(@record)
  end

  def note?
    @record.is_a?(JrcServiceDesk::TicketNote)
  end

  def origin_attributes
    { (note? ? :ticket_note : :ticket_event) => @record }
  end

  def author
    note? ? @record.author_membership : @record.actor_membership
  end

  def channels
    note? ? @record.notification_channels : %w[email whatsapp]
  end

  def publishable?
    return @record.visibility == 'customer' if note?
    return false unless type
    return JrcServiceDesk::NotificationEvent.public_task(@record).present? if type.start_with?('task_')

    true
  end

  def conversation(policy, channel)
    return @record.account.conversations.find_by(id: @record.notification_conversations[channel]) if note?
    return unless policy&.inbox_id

    conversations = @record.ticket.ticket_conversations.where(account_id: @record.account_id, unit_id: @record.unit_id)
    destinations = @record.account.conversations.where(id: conversations.select(:conversation_id), inbox_id: policy.inbox_id,
                                                       contact_id: @record.ticket.requester_id).limit(2).to_a
    destinations.first if destinations.one?
  end

  def fields
    captured = @record.data['notification_fields'] unless note?
    return captured.slice(*FIELDS) if captured.is_a?(Hash)

    current_fields
  end

  def current_fields
    ticket = @record.ticket
    task = JrcServiceDesk::NotificationEvent.public_task(@record) unless note?
    {
      'body' => note? ? @record.body : '', 'number' => ticket.id.to_s, 'title' => ticket.title,
      'status' => ticket.status.name, 'priority' => ticket.priority.name, 'queue' => ticket.queue&.name.to_s,
      'assignee' => assignee_name(ticket),
      'task_title' => task&.title.to_s, 'task_status' => task_status(task)
    }
  end

  def snapshot
    result = fields.merge('origin_type' => @record.class.name, 'origin_id' => @record.id.to_s, 'event_type' => type)
    result['origin_digest'] = JrcServiceDesk::CanonicalJson.digest(@record.data) unless note?
    result
  end

  def self.render(template, fields)
    FIELDS.reduce(template) { |content, field| content.gsub("{{#{field}}}", fields.fetch(field, '').to_s) }
  end

  private

  def assignee_name(ticket)
    ticket.assignee_membership&.account_user&.user&.name.to_s
  end

  def task_status(task)
    return '' unless task
    return @record.data.fetch('status', task.status) if @record.event_type == 'task_created'

    @record.data.fetch('changes', {})['status']&.last || task.status
  end
end
