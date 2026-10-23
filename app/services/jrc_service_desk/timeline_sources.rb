class JrcServiceDesk::TimelineSources
  def initialize(ticket:, context:)
    @ticket = ticket
    @context = context
  end

  def call(view: 'all')
    sources = {
      'note' => scope(JrcServiceDesk::TicketNote), 'event' => events(history: view == 'history'),
      'task' => scope(JrcServiceDesk::TicketTask), 'approval' => scope(JrcServiceDesk::TicketApproval),
      'message' => @context.account.messages.where(conversation_id: conversation_ids), 'delivery' => deliveries
    }
    sources['call'] = calls if defined?(::Call)
    case view
    when 'notes'
      sources.slice('note', 'message').merge(
        'note' => sources['note'].where(visibility: %w[internal technical_team]),
        'message' => sources['message'].where(private: true)
      )
    when 'conversations'
      sources.slice('note', 'message', 'delivery', 'call').merge(
        'note' => sources['note'].where(visibility: JrcServiceDesk::InteractionVisibility::PUBLIC),
        'message' => sources['message'].where(private: false)
      )
    when 'history' then sources.slice('event')
    when 'files'
      files = { 'note' => JrcServiceDesk::RecordWithdrawal.with_attachments(sources['note']),
                'message' => sources['message'].joins(:attachments).distinct }
      files['call'] = sources['call'].joins(:recording_attachment) if sources['call']
      files
    else sources
    end
  end

  def conversation_ids
    return [] unless JrcServiceDesk::TicketPolicy.new(@context.to_h, @ticket).view_conversations?

    @conversation_ids ||= @ticket.ticket_conversations.includes(:conversation).filter_map do |link|
      link.conversation_id if JrcServiceDesk::TicketConversationPolicy.new(@context.to_h, link).show?
    end
  end

  private

  def scope(model)
    Pundit.policy_scope!(@context.to_h, model).where(account_id: @ticket.account_id, unit_id: @ticket.unit_id, ticket_id: @ticket.id)
  end

  def events(history: false)
    rows = delivery_events
    rows = rows.where.not(event_type: %w[note_added interaction_republished task_created approval_requested]) unless history
    rows = rows.where.not(event_type: 'task_updated') unless @context.capability?(:tasks_view)
    rows = rows.where.not(event_type: 'approval_decided') unless @context.capability?(:approvals_view)
    audits = %w[notification_delivery_updated notification_resend_requested]
    visible = deliveries.select(:id).to_sql
    rows.where("event_type NOT IN (?) OR data->>'delivery_id' IN (SELECT id::text FROM (#{visible}) authorized_deliveries)", audits)
  end

  def deliveries
    notes = scope(JrcServiceDesk::TicketNote).select(:id)
    events = delivery_events.select(:id)
    rows = JrcServiceDesk::NotificationDelivery.where(account_id: @ticket.account_id, unit_id: @ticket.unit_id, ticket_id: @ticket.id)
    sources = rows.where(ticket_note_id: notes).or(rows.where(ticket_event_id: events))
    sources.where(conversation_id: [nil, *conversation_ids])
  end

  def delivery_events
    tasks = scope(JrcServiceDesk::TicketTask).select(:id).to_sql
    scope(JrcServiceDesk::TicketEvent).where(
      "event_type NOT IN (?) OR data->>'task_id' IN (SELECT id::text FROM (#{tasks}) authorized_tasks)",
      %w[task_created task_updated]
    )
  end

  def calls
    JrcCustomers::Visibility.new(**@context.to_h).calls(contact_ids: [@ticket.requester_id], conversation_ids: conversation_ids)
  end
end
