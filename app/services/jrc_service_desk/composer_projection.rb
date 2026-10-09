class JrcServiceDesk::ComposerProjection
  def initialize(ticket:, context:)
    @ticket = ticket
    @context = context
    @membership = context.active_memberships.find_by!(unit_id: ticket.unit_id)
  end

  def call
    {
      account_id: @ticket.account_id.to_s, unit_id: @ticket.unit_id.to_s, ticket_id: @ticket.id.to_s,
      audiences: audiences, recipient: recipient, channels: %w[email whatsapp].map { |channel| channel_options(channel) }
    }
  end

  def delivery(channel, conversation)
    note = JrcServiceDesk::TicketNote.new(account: @ticket.account, unit: @ticket.unit, ticket: @ticket,
                                          author_membership: @membership, visibility: 'customer', notification_channels: [channel])
    policy = JrcServiceDesk::NotificationEngine.current_policy(note, channel)
    JrcServiceDesk::NotificationDelivery.new(account: @ticket.account, unit: @ticket.unit, ticket: @ticket, ticket_note: note,
                                             execution_membership: @membership, conversation: conversation, channel: channel,
                                             notification_policy_version: policy)
  end

  private

  def audiences
    values = ['internal']
    values << 'technical_team' if @context.capability?(:technical_notes) && @context.native_team_ids.exists?(id: @ticket.team_id)
    values.concat(JrcServiceDesk::InteractionVisibility::PUBLIC) if @context.capability?(:customer_publish)
    values
  end

  def recipient
    contact = @ticket.requester
    return unless @context.capability?(:customers_view) && ContactPolicy.new(@context.to_h, contact).show?

    { id: contact.id.to_s, name: contact.name.to_s }
  end

  def channel_options(channel)
    links = @ticket.ticket_conversations.includes(conversation: :inbox)
    destinations = links.filter_map { |link| destination(link, channel) }
    { channel: channel, available: destinations.any? { |row| row[:available] },
      reason: destinations.empty? ? 'no_authorized_conversation' : nil, destinations: destinations }
  end

  def destination(link, channel)
    conversation = link.conversation
    return unless conversation.contact_id == @ticket.requester_id && JrcServiceDesk::NotificationEngine.channel(conversation.inbox) == channel
    return unless JrcServiceDesk::TicketConversationPolicy.new(@context.to_h, link).show?

    row = delivery(channel, conversation)
    reason = JrcServiceDesk::NotificationEngine.blocker(row)
    { conversation_id: conversation.id.to_s, display_id: conversation.display_id.to_s,
      recipient: JrcServiceDesk::NotificationEngine.recipient(conversation, channel).to_s,
      available: reason.nil?, reason: reason, policy_version_id: row.notification_policy_version_id&.to_s }
  end
end
