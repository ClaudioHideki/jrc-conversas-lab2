# Callback-free message persistence; caller holds the V2 authority transaction.
class JrcBroker::HistorySyncMessages
  def initialize(scope:, conversation:, input:)
    @scope = scope
    @conversation = conversation
    @input = input
  end

  def call
    # Message.store(coder: JSON) produces a JSON string in this Rails base.
    metadata = "CASE json_typeof(content_attributes) WHEN 'string' THEN (content_attributes #>> '{}')::jsonb " \
               "WHEN 'object' THEN content_attributes::jsonb ELSE '{}'::jsonb END"
    candidates = @scope.account.messages.where("(#{metadata})->>'jrc_broker_message_id' = ?", @input.fetch('broker_message_id'))
                       .reorder(:id).lock.limit(2).to_a
    raise ArgumentError, 'historical_message_ambiguous' if candidates.size > 1

    if candidates.one?
      message = candidates.first
      raise ArgumentError, 'historical_live_message_conflict' unless matching_candidate?(message)

      self.class.advance_status(message, @input.fetch('status'))
      return message
    end
    row = Message.insert_all!([message_attributes], returning: %w[id]) # rubocop:disable Rails/SkipsModelValidations
    @scope.account.messages.find(row.rows.first.first)
  end

  def self.advance_status(message, status)
    prior = { 'delivered' => ['sent'], 'read' => %w[sent delivered], 'failed' => ['sent'] }.fetch(status, [])
    return if prior.empty?

    # Compare-and-set against PostgreSQL, never a stale ORM status snapshot.
    Message.where(id: message.id, account_id: message.account_id, status: prior).update_all(status: Message.statuses.fetch(status)) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def matching_candidate?(message)
    expected = { 'inbox_id' => @scope.inbox.id, 'conversation_id' => @conversation.id, 'private' => false,
                 'content_type' => 'text', 'message_type' => @input.fetch('direction'), 'content' => @input.dig('content', 'text') }
    identity = history_metadata.except('jrc_broker_historical', 'jrc_broker_message_id')
    message.attributes.slice(*expected.keys) == expected && message.created_at.to_i == @input['occurred_at'] &&
      message.content_attributes.slice(*identity.keys) == identity && message.attachments.none?
  end

  def history_metadata
    { 'jrc_broker_historical' => true, 'jrc_broker_message_id' => @input.fetch('broker_message_id'),
      'jrc_broker_history_account_identity' => @input.fetch('history_account_identity'),
      'jrc_broker_provider_message_id' => @input.fetch('provider_message_id'), 'jrc_broker_participant_jid' => @input.fetch('participant_jid') }
  end

  def message_attributes
    incoming = @input.fetch('direction') == 'incoming'
    stamp = Time.at(@input.fetch('occurred_at')).utc
    source = ['jrc-history-v2', @input.fetch('organization_id'), @input.fetch('history_account_identity'),
              @input.fetch('broker_message_id')].join(':')
    { account_id: @scope.account.id, inbox_id: @scope.inbox.id, conversation_id: @conversation.id, source_id: source,
      content: @input.dig('content', 'text'), processed_message_content: @input.dig('content', 'text'),
      content_type: Message.content_types.fetch('text'), message_type: Message.message_types.fetch(@input.fetch('direction')),
      status: Message.statuses.fetch(@input.fetch('status')), private: false,
      sender_type: incoming ? 'Contact' : nil, sender_id: incoming ? @conversation.contact_id : nil,
      content_attributes: history_metadata, additional_attributes: {}, created_at: stamp, updated_at: stamp }
  end
end
