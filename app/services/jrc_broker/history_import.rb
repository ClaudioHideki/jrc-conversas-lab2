class JrcBroker::HistoryImport
  PROTOCOL = 'jrc-history-import/1'.freeze
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
  KEYS = %w[organization_id integration_id inbox_id broker_message_id content direction occurred_at status].freeze

  def initialize(account:, user:, access_token:)
    @authority = JrcFlowEffects::Authority.new(account: account, user: user, access_token: access_token)
  end

  def capability(inbox_id, organization_id, integration_id)
    Message.transaction do
      inbox = scope!(inbox_id, organization_id, integration_id)
      capability_fields(inbox, organization_id, integration_id)
    end
  end

  def call(conversation_id, input)
    validate!(input)
    Message.transaction do
      inbox = scope!(input.fetch('inbox_id'), input.fetch('organization_id'), input.fetch('integration_id'))
      conversation = @authority.account.conversations.lock.find_by!(display_id: Integer(conversation_id))
      raise ArgumentError, 'scope' unless conversation.inbox_id == inbox.id

      message = persist_message(conversation, input)
      receipt_scope(inbox, input).merge(conversation_id: conversation.display_id,
                                        broker_message_id: input.fetch('broker_message_id'), id: message.id)
    end
  end

  def bootstrap(inbox_id, input)
    raise ArgumentError, 'historical_bootstrap_request' unless input.is_a?(Hash) && input.keys.sort == JrcBroker::HistoryBootstrap::KEYS.sort

    Message.transaction do
      inbox = scope!(inbox_id, input.fetch('organization_id'), input.fetch('integration_id'))
      receipt = JrcBroker::HistoryBootstrap.new(inbox, input).call
      receipt_scope(inbox, input).merge(receipt)
    end
  end

  private

  def receipt_scope(inbox, input)
    capability_fields(inbox, input.fetch('organization_id'), input.fetch('integration_id')).except(:supports_text, :supports_silent_bootstrap)
  end

  def capability_fields(inbox, organization_id, integration_id)
    { protocol: PROTOCOL, account_id: inbox.account_id, inbox_id: inbox.id, organization_id: organization_id,
      integration_id: integration_id, supports_text: true, supports_silent_bootstrap: true }
  end

  def persist_message(conversation, input)
    source_id = "jrc-history:#{input.fetch('organization_id')}:#{input.fetch('broker_message_id')}"
    digest = Digest::SHA256.hexdigest((KEYS - ['status']).map { |key| input.fetch(key) }.to_json)
    message = @authority.account.messages.lock.find_by(source_id: source_id)
    return replay_message(message, conversation, digest, input.fetch('status')) if message

    # As in the Intercom importer: no delivery, live callbacks, reopen, SLA or assignment changes.
    attributes = message_attributes(conversation, input, digest).merge(source_id: source_id)
    inserted = Message.insert_all!([attributes], returning: %w[id]) # rubocop:disable Rails/SkipsModelValidations
    @authority.account.messages.find(inserted.rows.first.first)
  end

  def replay_message(message, conversation, digest, status)
    valid = message.conversation_id == conversation.id && message.content_attributes['jrc_history_request_hash'] == digest
    raise ArgumentError, 'conflict' unless valid

    advance_status(message, status)
    message
  end

  def advance_status(message, status)
    transitions = { 'sent' => %w[delivered read failed], 'delivered' => ['read'] }
    return unless transitions.fetch(message.status, []).include?(status)

    # Historical acknowledgements must not dispatch the model's live update event.
    message.update_columns(status: status) # rubocop:disable Rails/SkipsModelValidations
  end

  def message_attributes(conversation, input, digest)
    stamp = Time.at(input.fetch('occurred_at')).utc
    incoming = input.fetch('direction') == 'incoming'
    { account_id: conversation.account_id, inbox_id: conversation.inbox_id, conversation_id: conversation.id,
      content: input.fetch('content'), processed_message_content: input.fetch('content'), content_type: Message.content_types.fetch('text'),
      message_type: Message.message_types.fetch(input.fetch('direction')), status: Message.statuses.fetch(input.fetch('status')), private: false,
      sender_type: incoming ? 'Contact' : nil, sender_id: incoming ? conversation.contact_id : nil,
      content_attributes: { jrc_broker_message_id: input.fetch('broker_message_id'), jrc_broker_historical: true, jrc_history_request_hash: digest },
      additional_attributes: {}, created_at: stamp, updated_at: stamp }
  end

  def scope!(inbox_id, organization_id, integration_id)
    @authority.authorize!(lock: true)
    account = @authority.account
    raise ActiveRecord::RecordNotFound unless JrcBroker::Configuration.enabled? && account.feature_enabled?('jrc_broker')
    raise ArgumentError, 'identity' unless [organization_id, integration_id].all? { |value| UUID.match?(value.to_s) }

    integration = JrcBrokerIntegration.lock('FOR SHARE').find_by!(account_id: account.id)
    binding = JrcBrokerInboxBinding.lock('FOR SHARE').find_by!(account_id: account.id, inbox_id: Integer(inbox_id))
    raise ArgumentError, 'scope' unless integration.organization_id == organization_id && binding.integration_id == integration_id

    account.inboxes.lock('FOR SHARE').where(channel_type: 'Channel::Api').find(binding.inbox_id)
  end

  def validate!(input)
    valid = input.is_a?(Hash) && input.keys.sort == KEYS.sort && UUID.match?(input['broker_message_id'].to_s) &&
            input['inbox_id'].is_a?(Integer) && input['inbox_id'].positive?
    raise ArgumentError, 'request' unless valid

    validate_content!(input)
  end

  def validate_content!(input)
    valid = input['content'].is_a?(String) && input['content'].length.between?(1, 4096) &&
            %w[incoming outgoing].include?(input['direction']) && %w[sent delivered read failed].include?(input['status']) &&
            input['occurred_at'].is_a?(Integer) && input['occurred_at'].between?(0, Time.current.to_i)
    raise ArgumentError, 'request' unless valid
  end
end
