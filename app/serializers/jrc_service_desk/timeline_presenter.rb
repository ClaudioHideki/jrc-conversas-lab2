class JrcServiceDesk::TimelinePresenter
  def initialize(context:, ticket:)
    @context = context
    @ticket = ticket
    @presenter = JrcServiceDesk::Presenter.new(user_context: context.to_h)
  end

  def call(kind, record)
    common = { key: "#{kind}:#{record.id}", kind: kind, id: record.id.to_s, created_at: record.created_at.iso8601(6),
               account_id: @ticket.account_id.to_s, unit_id: @ticket.unit_id.to_s, ticket_id: @ticket.id.to_s }
    common.merge(send("#{kind}_payload", record), source: { type: kind, id: record.id.to_s })
  end

  private

  def note_payload(row)
    @presenter.related(row, 'notes')
  end

  def event_payload(row)
    @presenter.related(row, 'events')
  end

  def task_payload(row)
    Pundit.authorize(@context.to_h, row, :show?)
    { title: row.title, body: row.description, status: row.status, visibility: row.visibility,
      due_at: row.due_at&.iso8601(6), checklist: row.checklist, author: author(row.created_by_membership.account_user.user) }
  end

  def approval_payload(row)
    Pundit.authorize(@context.to_h, row, :show?)
    { title: row.title, body: row.description, status: row.status, due_at: row.due_at.iso8601(6),
      comment: row.comment, decided_at: row.decided_at&.iso8601(6), author: author(row.requested_by_membership.account_user.user) }
  end

  def message_payload(row)
    Pundit.authorize(@context.to_h, row.conversation, :show?)
    { body: row.content, private: row.private?, visibility: row.private? ? 'internal' : 'customer',
      conversation_id: row.conversation_id.to_s, message_type: row.message_type, status: row.status, author: author(row.sender),
      attachments: row.attachments.map { |file| attachment(file.file, file.id) } }
  end

  def call_payload(row)
    Pundit.authorize(@context.to_h, row.conversation, :show?)
    { conversation_id: row.conversation_id.to_s, status: row.status, direction: row.direction, body: row.transcript,
      duration_seconds: row.duration_seconds, started_at: row.started_at&.iso8601(6), ended_at: row.ended_at,
      author: author(row.accepted_by_agent), recordings: row.recording.attached? ? [attachment(row.recording, row.recording.id)] : [] }
  end

  def delivery_payload(row)
    JrcServiceDesk::DeliveryPresenter.new(context: @context).call(row).merge(author: author(row.execution_membership.account_user.user))
  end

  def author(record)
    record && { id: record.id.to_s, type: record.class.name, name: record.name.to_s }
  end

  def attachment(file, identifier)
    { id: identifier.to_s, filename: file.filename.to_s, scan_state: file.blob.metadata['service_desk_scan_state'] || 'unavailable' }
  end
end
