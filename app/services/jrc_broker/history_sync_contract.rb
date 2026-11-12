module JrcBroker::HistorySyncContract
  SCOPE_KEYS = %w[organization_id integration_id instance_id destination_revision history_account_identity].freeze
  BOOTSTRAP_KEYS = (SCOPE_KEYS + %w[broker_contact_id broker_conversation_id recipient occurred_at conversation_id]).freeze
  MESSAGE_KEYS = (SCOPE_KEYS + %w[broker_conversation_id broker_message_id provider_message_id content direction participant_jid occurred_at
                                  status]).freeze

  private

  def request_hash(input)
    # JSONB canonicalization makes object-key order independent across retries.
    semantic = input.except('status', 'instance_id', 'destination_revision')
    Digest::SHA256.hexdigest(canonical_json(semantic))
  end

  def canonical_json(value)
    case value
    when Hash then "{#{value.sort.map { |key, item| "#{key.to_json}:#{canonical_json(item)}" }.join(',')}}"
    when Array then "[#{value.map { |item| canonical_json(item) }.join(',')}]"
    # ActiveSupport String#to_json escapes HTML/separators and differs from
    # JSON.stringify. Protocol hashes use standard JSON UTF-8, not HTML-safe JSON.
    else JSON.generate(value)
    end
  end

  def validate_keys!(input, keys)
    raise ArgumentError, 'historical_request' unless input.is_a?(Hash) && input.keys.sort == keys.sort
  end

  def validate_ids!(input, keys)
    raise ArgumentError, 'historical_identity' unless keys.all? { |key| JrcBroker::HistoryImport::UUID.match?(input[key].to_s) }
  end

  def positive_integer?(value)
    value.is_a?(Integer) && value.positive?
  end

  def validate_time!(input)
    raise ArgumentError, 'historical_timestamp' unless input['occurred_at'].is_a?(Integer) && input['occurred_at'].between?(0, Time.current.to_i)
  end

  def validate_message!(input)
    validate_keys!(input, MESSAGE_KEYS)
    validate_ids!(input, %w[broker_conversation_id broker_message_id])
    validate_time!(input)
    valid = %w[incoming outgoing].include?(input['direction']) && %w[sent delivered read failed].include?(input['status']) &&
            bounded_string?(input['provider_message_id'], 256) && (text_content?(input['content']) || media_content?(input['content']))
    raise ArgumentError, 'historical_message' unless valid
  end

  def validate_participant!(recipient, input)
    participant = input.fetch('participant_jid')
    return if recipient['kind'] == 'GROUP' && input['direction'] == 'outgoing' && participant.nil?

    valid = recipient['kind'] == 'INDIVIDUAL' ? participant.nil? : individual_jid?(participant)
    raise ArgumentError, 'historical_participant' unless valid
  end

  def bounded_string?(value, maximum)
    value.is_a?(String) && value.length.between?(1, maximum)
  end

  def text_content?(content)
    content.is_a?(Hash) && content.keys.sort == %w[text type] && content['type'] == 'TEXT' && bounded_string?(content['text'], 4096)
  end

  def media_content?(content)
    content.is_a?(Hash) && content['type'] == 'MEDIA' && content['caption'].is_a?(String) && content['caption'].length <= 4096 &&
      content.keys.sort == (JrcBroker::HistorySyncMedia::KEYS + %w[type caption]).sort &&
      JrcBroker::HistorySyncMedia.valid_descriptor?(content.except('type', 'caption'))
  end

  def individual_jid?(value)
    value.is_a?(String) && JrcBroker::HistorySyncBootstrap::INDIVIDUAL.match?(value)
  end
end
