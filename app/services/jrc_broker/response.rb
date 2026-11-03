class JrcBroker::Response
  OPERATION_FIELDS = %w[operationId state stage instanceId integrationId inboxId lastError].freeze
  HEALTH_FIELDS = %w[integrationId inboxId instanceId integrationStatus instanceStatus transportStatus checkedAt lastError
                     callbackVerifiedAt lastSuccessfulInboundAt lastSuccessfulOutboundAt identityStatus identityApproved
                     identityRevision observedNumberSuffix allowedActions phoneNumber connectedAt lastSyncAt].freeze
  INSTANCE_FIELDS = %w[id organizationId providerAccountId name provider status createdAt updatedAt].freeze

  def self.operation(value)
    value.slice(*OPERATION_FIELDS)
  end

  def self.pair_operation(value, operation_id)
    unless value['operationId'] == operation_id && %w[PENDING SUCCEEDED FAILED UNKNOWN].include?(value['state']) &&
           [true, false].include?(value['reconciliationRequired'])
      raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE'
    end

    result = value.slice('operationId', 'state', 'reconciliationRequired')
    challenge = value['action']
    if challenge
      unless challenge.is_a?(Hash) && %w[QR_CODE PAIRING_CODE].include?(challenge['type'])
        raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE'
      end

      result['action'] = action(challenge)
    end
    result
  end

  def self.health(value, binding)
    valid = value.values_at('integrationId', 'inboxId', 'instanceId') == [binding.integration_id, binding.inbox_id, binding.instance_id]
    raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE' unless valid

    value.slice(*HEALTH_FIELDS)
  end

  def self.mutation(value, binding)
    raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE' unless value.dig('instance', 'id') == binding.instance_id

    result = value.slice('operationId', 'replayed', 'pending', 'reconciliationRequired')
    result['instance'] = value.fetch('instance').slice(*INSTANCE_FIELDS)
    result['action'] = action(value.fetch('action')) if value.key?('action')
    result
  end

  def self.action(value)
    validate_expiry!(value)

    case value['type']
    when 'QR_CODE'
      qr(value)
    when 'PAIRING_CODE'
      raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE' unless /\A[A-Za-z0-9-]{1,64}\z/.match?(value['code'].to_s)

      value.slice('type', 'code', 'expiresAt')
    when 'NONE'
      unless %w[ALREADY_CONNECTED CONNECTION_PENDING NO_USER_ACTION_REQUIRED].include?(value['reason'])
        raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE'
      end

      value.slice('type', 'reason')
    else
      raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE'
    end
  rescue ArgumentError, KeyError, TypeError
    raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE'
  end

  def self.validate_expiry!(value)
    return unless %w[QR_CODE PAIRING_CODE].include?(value['type'])
    return if Time.iso8601(value.fetch('expiresAt')) > Time.current

    raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE'
  end

  def self.qr(value)
    raw = value.fetch('value')
    valid = value['encoding'] == 'BASE64' || (value['encoding'] == 'DATA_URL' && raw.start_with?('data:image/png;base64,'))
    raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE' unless valid

    encoded = value['encoding'] == 'DATA_URL' ? raw.delete_prefix('data:image/png;base64,') : raw
    bytes = Base64.strict_decode64(encoded)
    raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE' unless bytes.start_with?("\x89PNG\r\n\x1a\n".b)

    value.slice('type', 'encoding', 'value', 'expiresAt')
  rescue ArgumentError, KeyError, NoMethodError
    raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE'
  end
end
