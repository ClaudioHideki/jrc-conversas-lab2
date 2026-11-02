class JrcCampaigns::BrokerConversationResolver
  MAX_CANDIDATES = 20
  REVISION_FIELDS = %w[ownerRevision attendanceRevision controlRevision destinationRevision credentialRevision].freeze

  def initialize(connector:, user:, phone_number:, contact: nil, conversation: nil)
    @connector = connector
    @user = user
    @phone = JrcCampaigns::PhoneNormalizer.call(phone_number)
    @contact = contact
    @conversation = conversation
    @inbox = connector.inbox
    @account = connector.inbox.account
  end

  def call
    authorize!
    @configuration = @connector.public_configuration.deep_dup
    contact = recipient_contact
    candidates = candidates_for(contact)
    identities = candidates.index_with { |candidate| local_identity!(candidate, contact) }
    # Only read requests run here, before the caller enters its local claim/message locks.
    client = @connector.context(@user, release_connection: true).client if candidates.any?
    matches = candidates.select { |candidate| proven?(client, candidate, contact) }
    validate_fresh!(contact, identities)
    raise ArgumentError, 'Mais de uma conversa foi confirmada pelo Broker. Revise o histórico deste contato.' if matches.many?
    raise ArgumentError, 'A conversa escolhida não possui vínculo confirmado pelo Broker.' if @conversation && matches.empty?

    matches.first
  end

  private

  def authorize!
    @account.reload
    member = @account.account_users.find_by(user_id: @user&.id)
    context = { account: @account, user: @user, account_user: member }
    return if JrcBrokerPolicy.new(context, nil).manage?

    raise JrcBroker::Client::Error.new('JRC_BROKER_FORBIDDEN', status: 403)
  end

  def recipient_contact
    contact = @contact&.reload
    unless contact
      contacts = @account.contacts.where(phone_number: @phone).limit(2).to_a
      raise ArgumentError, 'Mais de um contato possui o número destinatário.' if contacts.many?

      contact = contacts.first
    end
    validate_contact!(contact) if contact
    contact
  end

  def validate_contact!(contact)
    return if @phone.present? && [contact.account_id, JrcCampaigns::PhoneNormalizer.call(contact.phone_number)] == [@account.id, @phone]

    raise ArgumentError, 'Vínculo do contato incompatível com o número destinatário.'
  end

  def candidates_for(contact)
    return [@conversation.reload] if @conversation
    return [] unless contact

    candidates = @account.conversations.where(contact: contact, inbox: @inbox).includes(:contact_inbox)
                         .order(created_at: :desc, id: :desc).limit(MAX_CANDIDATES + 1).to_a
    raise ArgumentError, 'Revise o histórico do contato antes de escolher uma conversa para a campanha.' if candidates.size > MAX_CANDIDATES

    candidates
  end

  def local_identity!(conversation, contact)
    link = conversation.contact_inbox
    valid = contact && link && [conversation.account_id, conversation.inbox_id, conversation.contact_id] == [@account.id, @inbox.id, contact.id] &&
            [link.inbox_id, link.contact_id] == [@inbox.id, contact.id] && link.source_id.present?
    raise ArgumentError, 'Vínculo do contato incompatível com o número destinatário.' unless valid

    [conversation.id, conversation.display_id, conversation.contact_inbox_id, link.source_id]
  end

  def proven?(client, conversation, contact)
    snapshot = client.conversation_attendance(@connector.binding.integration_id, conversation.display_id)
    validate_snapshot!(snapshot, conversation, contact)
    true
  rescue JrcBroker::Client::Error => e
    raise unless e.status == 404

    false
  end

  def validate_snapshot!(snapshot, conversation, contact)
    expected = { 'organizationId' => @configuration.fetch('organization_id'), 'integrationId' => @configuration.fetch('integration_id'),
                 'accountId' => @account.id, 'inboxId' => @inbox.id, 'remoteContactId' => contact.id,
                 'remoteConversationId' => conversation.display_id, 'destinationRevision' => @configuration.fetch('destination_revision') }
    valid = snapshot.is_a?(Hash) && expected.all? { |key, value| snapshot[key] == value } && valid_snapshot_fields?(snapshot)
    raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE' unless valid
  end

  def valid_snapshot_fields?(snapshot)
    %w[BOT HUMAN].include?(snapshot['mode']) &&
      REVISION_FIELDS.all? { |key| snapshot[key].is_a?(Integer) && snapshot[key] >= 0 } &&
      %w[channelId conversationId].all? { |key| JrcBroker::Client::UUID.match?(snapshot[key].to_s) }
  end

  def validate_fresh!(contact, identities)
    authorize!
    validate_contact!(contact.reload) if contact
    fresh = JrcCampaigns::BrokerConnector.for(@inbox.reload)
    expected_callback = "#{@configuration.fetch('origin')}/v1/integrations/chatwoot/#{@configuration.fetch('integration_id')}/events"
    unless fresh && fresh.public_configuration == @configuration && @inbox.channel.webhook_url == expected_callback
      raise JrcBroker::Client::Error.new('JRC_BROKER_CONTEXT_CHANGED', status: 409)
    end

    identities.each do |conversation, identity|
      next if local_identity!(conversation.reload, contact) == identity

      raise ArgumentError, 'O vínculo do contato mudou. Revise uma nova prévia.'
    end
  end
end
