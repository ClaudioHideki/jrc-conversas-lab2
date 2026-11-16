class JrcBroker::LiveIngress
  include JrcBroker::LiveIngressContract
  class NotFound < StandardError; end
  class Backpressure < StandardError; end
  class Forbidden < StandardError; end

  def initialize(account:, user:, access_token:)
    @authority = JrcFlowEffects::Authority.new(account: account, user: user, access_token: access_token)
    @token_id = access_token&.id
    @token_sha256 = access_token && Digest::SHA256.hexdigest(access_token.token)
  end

  def capability(inbox_id, input)
    validate_keys!(input, SCOPE_KEYS)
    with_scope(inbox_id, input) do |scope|
      input.merge('account_id' => scope.account.id, 'inbox_id' => scope.inbox.id,
                  'supports_text' => true, 'supports_media' => true, 'supports_occurred_at' => true, 'max_media_bytes' => MAX_MEDIA_BYTES)
    end
  end

  def lookup(inbox_id, broker_message_id, input)
    validate_keys!(input, SCOPE_KEYS + ['request_hash'])
    raise ArgumentError, 'JRC_LIVE_INPUT' unless UUID.match?(broker_message_id.to_s) && HASH.match?(input['request_hash'].to_s)

    with_scope(inbox_id, input) do |scope|
      receipt = receipt_scope(scope, input).find_by(broker_message_id: broker_message_id)
      raise NotFound unless receipt
      raise ArgumentError, 'JRC_LIVE_CONFLICT' unless receipt.request_hash == input['request_hash'] &&
                                                      receipt.destination_revision == input['destination_revision']

      receipt.receipt_payload
    end
  end

  def receive(inbox_id, input, uploaded = nil)
    validate_message!(input)
    bytes = validated_upload(inbox_id, input, uploaded)
    receipt = with_scope(inbox_id, input) do |scope|
      # Account escrow budget precedes source lock consistently, avoiding lock upgrades.
      lock_key("jrc-live-budget:#{scope.account.id}") if bytes
      JrcBroker::IngressIdentity.lock!(scope, input)
      prior = receipt_scope(scope, input).lock.find_by(broker_message_id: input['broker_message_id'])
      if prior
        raise ArgumentError, 'JRC_LIVE_CONFLICT' unless prior.request_hash == input['request_hash']

        prior
      else
        reserve!(scope, input, bytes)
      end
    end
    enqueue(receipt) if receipt.state == 'MEDIA_PENDING'
    receipt.receipt_payload
  end

  def with_scope(inbox_id, input)
    validate_scope!(input)
    Message.transaction do
      scope = JrcBroker::HistoryScope.new(@authority).call(inbox_id, input['organization_id'], input['integration_id'])
      valid = scope.binding.instance_id == input['instance_id'] && scope.integration.destination_revision == input['destination_revision']
      raise ArgumentError, 'JRC_LIVE_SCOPE' unless valid

      yield scope
    end
  rescue ActiveRecord::RecordNotFound
    raise ArgumentError, 'JRC_LIVE_SCOPE'
  rescue Pundit::NotAuthorizedError
    raise Forbidden
  end

  def publish!(scope, input, blob = nil)
    JrcBroker::IngressIdentity.assert_no_unproven_message!(scope, input)
    conversation = scope.account.conversations.where(inbox_id: scope.inbox.id).lock.find_by!(display_id: input.fetch('conversation_id'))
    clock = Time.at(input.fetch('occurred_at')).utc if input.key?('occurred_at')
    initialize_activity_clock(conversation, clock)
    attrs = { 'jrc_broker_message_id' => input.fetch('broker_message_id') }
    attrs['external_echo'] = true if input['message_origin'] == 'EXTERNAL_OBSERVED'
    Messages::MessageBuilder.new(nil, conversation,
                                 content: input.fetch('content'), message_type: input.fetch('message_type'), private: false,
                                 content_attributes: attrs, attachments: blob ? [blob] : []).perform do |message|
      message.created_at = clock if clock
    end
  end

  private

  def initialize_activity_clock(conversation, clock)
    return unless clock && !conversation.messages.exists?

    # The caller holds this conversation's row lock. Replace only the empty
    # conversation's arrival default; no existing message clock is rewritten.
    conversation.update_columns(last_activity_at: clock) # rubocop:disable Rails/SkipsModelValidations
  end

  def validated_upload(inbox_id, input, uploaded)
    if input['media'].nil?
      raise ArgumentError, 'JRC_LIVE_FILE' unless uploaded.nil?

      return nil
    end
    raise ArgumentError, 'JRC_LIVE_FILE' unless uploaded.respond_to?(:read)

    # Recheck authority before reading even the bounded local multipart file.
    bytes = with_scope(inbox_id, input) { |_scope| uploaded.read(MAX_MEDIA_BYTES + 1) }
    JrcBroker::LiveIngressMedia.new.verify_bytes!(bytes, input.fetch('media'))
    bytes
  end

  def receipt_scope(scope, input)
    JrcBrokerLiveReceipt.where(account_id: scope.account.id, inbox_id: scope.inbox.id,
                               **input.slice('organization_id', 'integration_id', 'instance_id').symbolize_keys)
  end

  def reserve!(scope, input, bytes)
    scope.account.conversations.where(inbox_id: scope.inbox.id).find_by!(display_id: input.fetch('conversation_id'))
    attributes = receipt_attributes(scope, input)
    historical = JrcBroker::LiveHistoryCustody.new(scope).historical_message(input)
    if historical
      blob = historical.attachments.first&.file&.blob
      return JrcBrokerLiveReceipt.create!(**attributes, state: 'PERSISTED', message: historical, blob: blob)
    end
    if bytes
      JrcBroker::IngressIdentity.assert_no_unproven_message!(scope, input)
      blob = reserve_blob!(scope, input.fetch('media'), bytes)
      JrcBrokerLiveReceipt.create!(**attributes, state: 'MEDIA_PENDING', staged_bytes: bytes, blob: blob)
    else
      message = publish!(scope, input)
      JrcBrokerLiveReceipt.create!(**attributes, state: 'PERSISTED', message: message, published_at: Time.current)
    end
  end

  def receipt_attributes(scope, input)
    input.slice('organization_id', 'integration_id', 'instance_id', 'destination_revision', 'broker_message_id', 'conversation_id',
                'request_hash').symbolize_keys.merge(account: scope.account, inbox: scope.inbox, envelope: input,
                                                     user: @authority.user, access_token_id: @token_id, access_token_sha256: @token_sha256)
  end

  def reserve_blob!(scope, descriptor, bytes)
    pending_size = JrcBrokerLiveReceipt.where(account_id: scope.account.id, state: 'MEDIA_PENDING').sum('octet_length(staged_bytes)')
    raise Backpressure if pending_size + bytes.bytesize > MAX_PENDING_BYTES

    ActiveStorage::Blob.create_before_direct_upload!(filename: descriptor.fetch('filename'), content_type: descriptor.fetch('mime_type'),
                                                     byte_size: bytes.bytesize, checksum: Digest::MD5.base64digest(bytes))
  end

  def lock_key(value)
    connection = ApplicationRecord.connection
    connection.execute("SELECT pg_advisory_xact_lock(hashtextextended(#{connection.quote(value)},0))")
  end

  def enqueue(receipt)
    JrcBroker::LiveIngressMediaJob.perform_later(receipt.id)
  rescue StandardError
    # A committed pending receipt is the recovery authority, including a lost enqueue.
    nil
  end
end
