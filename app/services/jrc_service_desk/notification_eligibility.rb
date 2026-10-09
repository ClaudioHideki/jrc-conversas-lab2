class JrcServiceDesk::NotificationEligibility
  def initialize(row)
    @row = row
    member = row.execution_membership.account_user
    @context = JrcServiceDesk::OperationalContext.new(account: row.account, user: member.user, account_user: member)
    @source = JrcServiceDesk::NotificationSource.new(row.ticket_note || row.ticket_event)
  end

  def blocker
    authorization_blocker || policy_blocker || conversation_blocker || channel_blocker || recipient_blocker || snapshot_blocker
  end

  private

  def authorization_blocker
    return 'authorization_revoked' unless operator_allowed?
    return 'visibility_not_customer' unless @source.publishable?
    return 'authorization_revoked' unless Pundit.policy!(@context.to_h, @row.ticket_note || @row.ticket_event).show?
    return 'authorization_revoked' unless task_allowed?
    return 'channel_not_selected' unless @source.channels.include?(@row.channel)

    nil
  end

  def operator_allowed?
    @context.unit_allowed?(@row.unit) && @context.capability?(:customer_publish)
  end

  def task_allowed?
    return true unless @row.ticket_event && @source.type&.start_with?('task_')

    task = JrcServiceDesk::NotificationEvent.public_task(@row.ticket_event)
    task && JrcServiceDesk::TicketTaskPolicy.new(@context.to_h, task).show?
  end

  def policy_blocker
    current = JrcServiceDesk::NotificationEngine.current_policy(@row.ticket_note || @row.ticket_event, @row.channel)
    'policy_disabled_or_changed' unless current&.enabled? && current.id == @row.notification_policy_version_id
  end

  def conversation_blocker
    conversation = @row.conversation
    return 'recipient_missing' unless conversation && conversation.contact_id == @row.ticket.requester_id
    return 'recipient_blocked' if conversation.contact.blocked?
    return 'conversation_not_linked' unless @row.ticket.ticket_conversations.exists?(conversation_id: conversation.id)

    permitted = JrcServiceDesk::NativeExecutionContext.with(@context.to_h) { ConversationPolicy.new(@context.to_h, conversation).show? }
    'conversation_denied' unless permitted
  end

  def channel_blocker
    conversation = @row.conversation
    policy = @row.notification_policy_version
    return 'channel_unavailable' unless conversation.inbox_id == policy.inbox_id && native_channel_ready?(conversation)
    return unless @row.channel == 'email'

    email = conversation.inbox.channel
    'smtp_unavailable' unless smtp_ready?(email) || oauth_ready?(email) || ENV['SMTP_ADDRESS'].present?
  end

  def native_channel_ready?(conversation)
    JrcServiceDesk::NotificationEngine.channel(conversation.inbox) == @row.channel && conversation.can_reply?
  end

  def smtp_ready?(email)
    email.smtp_enabled? && email.smtp_address.present? && email.smtp_port.to_i.positive?
  end

  def oauth_ready?(email)
    email.imap_enabled? && (email.microsoft? || email.google?) && email.provider_config.to_h['access_token'].present?
  end

  def recipient_blocker
    return 'recipient_preference' unless JrcServiceDesk::ContactNotificationPreferences.channels(@row.ticket.requester).include?(@row.channel)

    current = JrcServiceDesk::NotificationEngine.recipient(@row.conversation, @row.channel)
    return 'recipient_missing' if current.blank?

    'recipient_changed' if @row.recipient.present? && current != @row.recipient
  end

  def snapshot_blocker
    return unless @row.ticket_event_id

    'event_payload_changed' unless @row.source_snapshot['origin_id'] == @row.ticket_event_id.to_s &&
                                   @row.source_snapshot['event_type'] == @source.type &&
                                   @row.source_snapshot['origin_digest'] == JrcServiceDesk::CanonicalJson.digest(@row.ticket_event.data) &&
                                   @row.source_digest == JrcServiceDesk::CanonicalJson.digest(@row.source_snapshot)
  end
end
