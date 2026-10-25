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
    actor = @row.execution_membership
    actor.reload if actor.persisted?
    grant = actor.administrative_actor? ? @context.administrator? : actor.active?
    grant && @context.unit_allowed?(@row.unit) && @context.capability?(:customer_publish)
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
    return 'recipient_missing' unless conversation && conversation.contact_id == (@row.recipient_contact_id || @row.ticket.requester_id)
    return 'recipient_blocked' if conversation.contact.blocked?
    return 'recipient_denied' unless JrcServiceDesk::NotificationControls.contact_allowed?(@row.ticket, conversation.contact, @context)
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
    return false unless JrcServiceDesk::NotificationEngine.channel(conversation.inbox) == @row.channel

    configured = @row.notification_policy_version.settings['whatsapp_template']
    if @row.channel == 'whatsapp' && configured.present?
      JrcServiceDesk::NotificationWhatsappTemplate.new(inbox: conversation.inbox, configuration: configured).validate!
      return true
    end
    conversation.can_reply?
  rescue ArgumentError, KeyError
    false
  end

  def smtp_ready?(email)
    email.smtp_enabled? && email.smtp_address.present? && email.smtp_port.to_i.positive?
  end

  def oauth_ready?(email)
    email.imap_enabled? && (email.microsoft? || email.google?) && email.provider_config.to_h['access_token'].present?
  end

  def recipient_blocker
    unless JrcServiceDesk::ContactNotificationPreferences.channels(@row.recipient_contact || @row.ticket.requester).include?(@row.channel)
      return 'recipient_preference'
    end

    controls = JrcServiceDesk::NotificationControls.new(@row.notification_policy_version.settings)
    return 'recipient_removed' unless controls.recipient_ids(@row.ticket).include?(@row.recipient_contact_id || @row.ticket.requester_id)

    return 'internal_copy_revoked' if @row.channel == 'email' && !controls.authorized_copies?(@row.ticket, @row.source_snapshot)

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
