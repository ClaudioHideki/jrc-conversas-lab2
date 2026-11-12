class JrcBroker::HistorySyncV2
  include JrcBroker::HistorySyncContract

  PROTOCOL = 'jrc-history-sync/2'.freeze

  def initialize(account:, user:, access_token:)
    @authority = JrcFlowEffects::Authority.new(account: account, user: user, access_token: access_token)
    @access_token_id = access_token&.id
    @access_token_sha256 = access_token && Digest::SHA256.hexdigest(access_token.token)
  end

  def self.lock_key(value)
    connection = ApplicationRecord.connection
    connection.execute("SELECT pg_advisory_xact_lock(hashtextextended(#{connection.quote(value)},0))")
  end

  def capability(inbox_id, input)
    validate_keys!(input, SCOPE_KEYS)
    Message.transaction do
      scope = scope!(inbox_id, input)
      envelope(scope, input).merge(supports_text: true, supports_groups: true, supports_media: true,
                                   max_media_bytes: JrcBroker::HistorySyncMedia::MAX_BYTES, supports_silent_bootstrap: true)
    end
  end

  def bootstrap(inbox_id, input)
    validate_keys!(input, BOOTSTRAP_KEYS)
    validate_time!(input)
    validate_ids!(input, %w[broker_contact_id broker_conversation_id])
    valid = input['recipient'].is_a?(Hash) && (input['conversation_id'].nil? || positive_integer?(input['conversation_id']))
    raise ArgumentError, 'historical_bootstrap_request' unless valid

    Message.transaction do
      scope = scope!(inbox_id, input)
      digest = request_hash(input)
      receipt = find_receipt(scope, input, 'CHAT', input.fetch('broker_conversation_id'))
      if receipt
        raise ArgumentError, 'historical_conflict' unless receipt.request_hash == digest
      else
        result = JrcBroker::HistorySyncBootstrap.new(scope, input).call
        receipt = persist_receipt(scope, input, 'CHAT', digest, result)
      end
      receipt_payload(scope, input, receipt)
    end
  end

  def call(inbox_id, input)
    validate_message!(input)
    result = Message.transaction do
      scope = scope!(inbox_id, input)
      route = find_receipt(scope, input, 'CHAT', input.fetch('broker_conversation_id'))
      raise ActiveRecord::RecordNotFound unless route

      validate_participant!(route.recipient, input)
      receipt = receive_message(scope, input, route)
      JrcBroker::HistorySyncMedia.bind!(scope, input, receipt)
      receipt_payload(scope, input, receipt)
    end
    # The durable ATTACH_PENDING row, not this enqueue, owns completion.
    media = JrcBrokerHistoryMedia.joins(:receipt).find_by(jrc_broker_history_receipts: { receipt_id: result[:receipt_id] }, state: 'ATTACH_PENDING')
    JrcBroker::HistorySyncMediaJob.perform_later(media.id) if media
    result
  end

  def receipt(inbox_id, receipt_id, input)
    validate_keys!(input, SCOPE_KEYS)
    validate_ids!({ 'receipt_id' => receipt_id }, %w[receipt_id])
    Message.transaction do
      scope = scope!(inbox_id, input)
      receipt = receipt_scope(scope, input).find_by!(receipt_id: receipt_id)
      receipt_payload(scope, input, receipt)
    end
  end

  def with_scope(inbox_id, input)
    validate_keys!(input, SCOPE_KEYS)
    Message.transaction do
      scope = scope!(inbox_id, input)
      yield(scope, @authority.user, @access_token_id, @access_token_sha256)
    end
  end

  private

  def receive_message(scope, input, route)
    digest = request_hash(input)
    receipt = find_receipt(scope, input, 'MESSAGE', input.fetch('broker_message_id'))
    if receipt
      raise ArgumentError, 'historical_conflict' unless receipt.request_hash == digest && receipt.conversation_id == route.conversation_id

      JrcBroker::HistorySyncMessages.advance_status(receipt.message, input.fetch('status'))
      return receipt
    end
    conversation = scope.account.conversations.lock.find(route.conversation_id)
    message = JrcBroker::HistorySyncMessages.new(scope: scope, conversation: conversation, input: input).call
    if message.created_at > conversation.last_activity_at
      conversation.update_columns(last_activity_at: message.created_at) # rubocop:disable Rails/SkipsModelValidations
    end
    persist_receipt(scope, input, 'MESSAGE', digest,
                    contact: route.contact, conversation: conversation, recipient: route.recipient, message: message)
  end

  def scope!(inbox_id, input)
    raise ActiveRecord::RecordNotFound unless ENV['JRC_HISTORY_SYNC_V2_ENABLED'] == 'true'

    validate_ids!(input, %w[organization_id integration_id instance_id history_account_identity])
    scope = JrcBroker::HistoryScope.new(@authority).call(inbox_id, input.fetch('organization_id'), input.fetch('integration_id'))
    revision = Integer(input.fetch('destination_revision').to_s, 10)
    raise ArgumentError, 'historical_destination_changed' unless revision.positive? && scope.integration.destination_revision == revision &&
                                                                 scope.binding.instance_id == input.fetch('instance_id')

    scope
  end

  def receipt_scope(scope, input)
    JrcBrokerHistoryReceipt.where(account_id: scope.account.id, inbox_id: scope.inbox.id,
                                  organization_id: input.fetch('organization_id'), integration_id: input.fetch('integration_id'),
                                  history_account_identity: input.fetch('history_account_identity'))
  end

  def find_receipt(scope, input, kind, source_id)
    self.class.lock_key(['jrc-history-v2', scope.account.id, scope.inbox.id, input.fetch('integration_id'),
                         input.fetch('history_account_identity'), kind, source_id].join(':'))
    receipt_scope(scope, input).lock.find_by(record_kind: kind, source_id: source_id)
  end

  def persist_receipt(scope, input, kind, digest, result)
    source_id = input.fetch(kind == 'CHAT' ? 'broker_conversation_id' : 'broker_message_id')
    JrcBrokerHistoryReceipt.create!(account: scope.account, inbox: scope.inbox, contact: result.fetch(:contact),
                                    conversation: result.fetch(:conversation), message: result[:message],
                                    receipt_id: SecureRandom.uuid, organization_id: input.fetch('organization_id'),
                                    integration_id: input.fetch('integration_id'), history_account_identity: input.fetch('history_account_identity'),
                                    source_id: source_id, broker_conversation_id: input.fetch('broker_conversation_id'),
                                    record_kind: kind, request_hash: digest, recipient: result.fetch(:recipient), created_at: Time.current)
  end

  def envelope(scope, input)
    { protocol: PROTOCOL, account_id: scope.account.id, inbox_id: scope.inbox.id, organization_id: input.fetch('organization_id'),
      integration_id: input.fetch('integration_id'), history_account_identity: input.fetch('history_account_identity'),
      destination_revision: scope.integration.destination_revision }
  end

  def receipt_payload(scope, input, receipt)
    media = JrcBrokerHistoryMedia.find_by(receipt_id: receipt.id)
    envelope(scope, input).merge(receipt_id: receipt.receipt_id, request_hash: receipt.request_hash,
                                 state: media && media.state != 'READY' ? 'MEDIA_PENDING' : 'PERSISTED',
                                 conversation_id: receipt.conversation.display_id, contact_id: receipt.contact_id,
                                 source_id: receipt.conversation.contact_inbox.source_id,
                                 broker_conversation_id: receipt.broker_conversation_id,
                                 broker_message_id: receipt.record_kind == 'MESSAGE' ? receipt.source_id : nil, message_id: receipt.message_id)
                          .merge(media&.state == 'READY' ? { media_sha256: media.descriptor.fetch('sha256') } : {})
  end
end
