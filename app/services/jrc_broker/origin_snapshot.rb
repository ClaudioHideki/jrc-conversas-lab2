# A cached identity proof, not a claim of current WhatsApp availability.
# No remote calls, provider configuration, contact phone or credentials are used.
class JrcBroker::OriginSnapshot
  SCOPE = %w[integrationId instanceId inboxId].freeze
  FIELDS = (SCOPE + %w[identityRevision phoneNumber checkedAt]).freeze
  PHONE = /\A\+?([1-9]\d{7,14})\z/
  VALID_FOR_SECONDS = 15 * 60

  def self.capture(binding, health, previous: nil)
    return unless matching_scope?(binding, health)
    return unless health['identityRevision'].is_a?(Integer) && health['identityRevision'] >= 0

    same_identity = previous.is_a?(Hash) && previous.values_at(*SCOPE, 'identityRevision') == health.values_at(*SCOPE, 'identityRevision')
    match = PHONE.match(health['phoneNumber']) if health['phoneNumber'].is_a?(String)
    unless confirmed?(health) && match && timestamp(health['checkedAt'])
      return previous.merge('suspended' => true) if same_identity

      return
    end

    snapshot = health.slice(*FIELDS).merge('phoneNumber' => "+#{match[1]}")
    if same_identity && (previous['conflict'] || previous['phoneNumber'] != snapshot['phoneNumber'])
      snapshot = snapshot.merge('phoneNumber' => nil, 'conflict' => true)
    end
    snapshot
  end

  def self.project(binding, now: Time.now)
    context = binding.connection_state || {}
    origin = context['origin']
    return public_value('UNKNOWN') unless origin.is_a?(Hash)

    health = context.fetch('health', {})
    checked_at = timestamp(origin['checkedAt'])
    valid = matching_scope?(binding, origin) && matching_scope?(binding, health) && confirmed?(health) &&
            health['identityRevision'] == origin['identityRevision'] && !origin['conflict'] && !origin['suspended'] &&
            checked_at && checked_at <= now + 300 && now < checked_at + VALID_FOR_SECONDS && PHONE.match?(origin['phoneNumber'].to_s)
    valid ? public_value('VERIFIED', origin['phoneNumber'], origin['checkedAt']) : public_value('STALE')
  end

  def self.matching_scope?(binding, value)
    value.is_a?(Hash) && value.values_at(*SCOPE) == [binding.integration_id, binding.instance_id, binding.inbox_id]
  end

  def self.confirmed?(health)
    health['identityApproved'] == true && health['identityStatus'] == 'CONFIRMED'
  end

  def self.timestamp(value)
    Time.iso8601(value) if value.is_a?(String)
  rescue ArgumentError
    nil
  end

  def self.public_value(status, number = nil, checked_at = nil)
    { 'own_number' => number, 'number_status' => status, 'verified_at' => checked_at,
      'valid_until' => checked_at && (Time.iso8601(checked_at) + VALID_FOR_SECONDS).utc.iso8601 }
  end
  private_class_method :confirmed?, :timestamp, :public_value
end
