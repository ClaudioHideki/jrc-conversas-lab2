class JrcServiceDesk::NotificationSource
  FIELDS = %w[body number title status priority queue assignee task_title task_status customer_name company_name operator_company].freeze

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

  def conversation(policy, channel, contact_id: @record.ticket.requester_id)
    return @record.account.conversations.find_by(id: @record.notification_conversations[channel]) if note?
    return unless policy&.inbox_id

    conversations = @record.ticket.ticket_conversations.where(account_id: @record.account_id, unit_id: @record.unit_id)
    destinations = @record.account.conversations.where(id: conversations.select(:conversation_id), inbox_id: policy.inbox_id,
                                                       contact_id: contact_id).limit(2).to_a
    destinations.first if destinations.one?
  end

  def condition_fields
    note? ? @record.notification_context : @record.data['notification_context']
  end

  def fields
    captured = note? ? @record.notification_context['fields'] : @record.data['notification_fields']
    return captured.slice(*FIELDS) if captured.is_a?(Hash)

    current_fields
  end

  def current_fields
    ticket = @record.ticket
    task = JrcServiceDesk::NotificationEvent.public_task(@record) unless note?
    {
      'body' => note? ? @record.body : '', 'number' => ticket.id.to_s, 'title' => ticket.title,
      'status' => ticket.status.name, 'priority' => ticket.priority.name, 'queue' => ticket.queue&.name.to_s,
      'assignee' => assignee_name(ticket), 'customer_name' => ticket.requester.name.to_s,
      'company_name' => ticket.requester.company&.name.to_s, 'operator_company' => ticket.unit.operator_company.name.to_s,
      'task_title' => task&.title.to_s, 'task_status' => task_status(task)
    }
  end

  def snapshot
    result = fields.merge('origin_type' => @record.class.name, 'origin_id' => @record.id.to_s, 'event_type' => type)
    result['origin_digest'] = JrcServiceDesk::CanonicalJson.digest(@record.data) unless note?
    captured = condition_fields
    result['assignee_account_user_id'] = captured['assignee_account_user_id'] if captured.is_a?(Hash)
    result
  end

  def self.render(template, fields)
    template.gsub(/\{\{(.*?)\}\}/) do |token|
      field = Regexp.last_match(1)
      FIELDS.include?(field) ? fields.fetch(field, '').to_s : token
    end
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
