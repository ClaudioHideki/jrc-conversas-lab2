# frozen_string_literal: true

# Only native Service Desk blobs require this additional check. Ordinary Chatwoot
# attachments retain their native behavior. A signed blob URL is not SD authority.
class JrcServiceDesk::ProtectedBlobAccess
  def initialize(blob:, user:, grant_id: nil, widget_contact_inbox: nil, widget_conversations: nil, portal_scope: nil)
    @blob, @user, @grant_id = blob, user, grant_id
    @widget_contact_inbox, @widget_conversations = widget_contact_inbox, widget_conversations
    @portal_scope = portal_scope
  end

  def protected?
    protected_records.any?
  end

  def allowed?
    return false unless @blob.metadata['service_desk_scan_state'] == 'clean'
    return protected_records.all? { |record| widget_allowed?(record) } if @widget_contact_inbox
    # Only an already verified, server-built PortalScope may enter this branch.
    # A Portal download must never borrow the same User's operational authority.
    return protected_records.all? { |record| portal_allowed?(record, @portal_scope) } if @portal_scope
    return false unless @user&.active_for_authentication?

    protected_records.all? { |record| operator_allowed?(record) || requester_allowed?(record) }
  end

  private

  # This context is supplied only by the native JWT widget controller. Every
  # protected owner must be public in that visitor's current native scope, so a
  # signed_id reattached from an internal note, call or other visitor stays denied.
  def widget_allowed?(record)
    return false unless record.is_a?(::Attachment) && @widget_conversations

    message = record.message
    inbox = @widget_contact_inbox.inbox
    return false if message.private? || message.activity?
    return false unless record.account_id == inbox.account_id && message.account_id == inbox.account_id && message.inbox_id == inbox.id

    @widget_conversations.where(account_id: inbox.account_id, inbox_id: inbox.id, contact_id: @widget_contact_inbox.contact_id)
                         .exists?(id: message.conversation_id)
  end

  def protected_records
    @protected_records ||= @blob.attachments.includes(:record).filter_map do |attachment|
      record = attachment.record
      next record if record.is_a?(JrcServiceDesk::TicketNote)
      next record if record.is_a?(JrcServiceDesk::IncidentEntry)
      next unless record.is_a?(::Attachment) || call_record?(record)
      next unless JrcServiceDesk::TicketConversation.exists?(account_id: record.account_id, conversation_id: conversation_id(record))

      record
    end
  end

  def tickets_for(record)
    return JrcServiceDesk::Ticket.where(id: record.ticket_id, account_id: record.account_id) if record.is_a?(JrcServiceDesk::TicketNote)

    JrcServiceDesk::Ticket.where(account_id: record.account_id, id: JrcServiceDesk::TicketConversation.where(
      account_id: record.account_id, conversation_id: conversation_id(record)
    ).select(:ticket_id))
  end

  def operator_allowed?(record)
    # Case files retain their own authorized/scanned Case download endpoint.
    return false if record.is_a?(JrcServiceDesk::IncidentEntry)

    account = record.account
    member = account.account_users.find_by(user_id: @user.id)
    return false unless member

    context = JrcServiceDesk::OperationalContext.new(account: account, user: @user, account_user: member)
    tickets_for(record).any? do |ticket|
      ticket_policy = JrcServiceDesk::TicketPolicy.new(context.to_h, ticket)
      next false unless ticket_policy.show? && !JrcServiceDesk::RecordWithdrawal.withdrawn?(ticket, :ticket)

      if record.is_a?(JrcServiceDesk::TicketNote)
        ticket_policy.view_notes? && JrcServiceDesk::TicketNotePolicy.new(context.to_h, record).show? &&
          JrcServiceDesk::RecordWithdrawal.attachments(record).any? { |file| file.blob_id == @blob.id }
      elsif call_record?(record)
        call_allowed?(record, ticket, context)
      else
        link = ticket.ticket_conversations.find_by(conversation_id: record.message.conversation_id)
        ticket_policy.view_conversations? && link && JrcServiceDesk::NativeExecutionContext.with(context.to_h) do
          JrcServiceDesk::TicketConversationPolicy.new(context.to_h, link).show?
        end
      end
    end
  end

  def requester_allowed?(record)
    grant = JrcServiceDesk::PortalGrant.available_for(@user).find { |row| row.id.to_s == @grant_id.to_s }
    return false unless grant

    scope = JrcServiceDesk::RequesterPortalScope.new(grant: grant, user: @user)
    portal_allowed?(record, scope)
  end

  def portal_allowed?(record, scope)
    return false if record.is_a?(JrcServiceDesk::IncidentEntry) || call_record?(record)

    tickets_for(record).any? do |ticket|
      next false unless scope.tickets.exists?(id: ticket.id)

      if record.is_a?(JrcServiceDesk::TicketNote)
        scope.notes(ticket).exists?(id: record.id) && JrcServiceDesk::RecordWithdrawal.attachments(record).any? { |file| file.blob_id == @blob.id }
      else
        message = record.message
        incoming = !message.private? && message.incoming? && message.sender == ticket.requester &&
          message.content_attributes['service_desk_ticket_id'].to_s == ticket.id.to_s &&
          scope.conversations.exists?(id: message.conversation_id)
        incoming || JrcServiceDesk::PortalPublicMessages.new(scope: scope, ticket: ticket).messages.any? { |row| row.id == message.id }
      end
    end
  end

  def call_record?(record)
    defined?(::Call) && record.is_a?(::Call)
  end

  def conversation_id(record)
    record.is_a?(::Attachment) ? record.message.conversation_id : record.conversation_id
  end

  def call_allowed?(record, ticket, context)
    JrcServiceDesk::NativeExecutionContext.with(context.to_h) do
      file = JrcServiceDesk::TimelineAttachment.new(ticket: ticket, context: context).call(
        kind: 'call', record_id: record.id, attachment_id: record.recording.id
      )
      file.blob_id == @blob.id
    end
  rescue ActiveRecord::RecordNotFound, JrcServiceDesk::AttachmentScanError
    false
  end
end
