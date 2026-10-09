# frozen_string_literal: true

class JrcNico::Helpdesk::EmailClaim
  def initialize(receipt)
    @receipt = receipt
  end

  def fingerprints
    source = @receipt.source
    email = JrcNico::Helpdesk::DeliveryAuthorization.new(source, @receipt.recipient).email!
    pointer = JrcNico::Helpdesk::EmailPointer.url(source)
    { payload_digest: JrcNico::Helpdesk::Definition.digest('source_id' => source.id, 'policy_id' => source.policy_version_id,
                                                           'recipient_id' => @receipt.recipient_id, 'channel' => 'email', 'pointer' => pointer,
                                                           'payload' => source_payload(source)),
      routing_digest: JrcNico::Helpdesk::Definition.digest('account_id' => source.account_id,
                                                           'recipient_id' => @receipt.recipient_id, 'policy_id' => source.policy_version_id,
                                                           'confirmed_email' => email) }
  end

  def verify!
    @receipt.reload
    valid = @receipt.state == 'dispatching' && @receipt.claim_token.present? && @receipt.attempt_number.positive?
    valid &&= fingerprints.all? { |key, digest| @receipt.public_send(key) == digest }
    raise Pundit::NotAuthorizedError unless valid

    @receipt
  end

  private

  def source_payload(source)
    return source.payload unless source.is_a?(JrcNico::Helpdesk::Event)

    { 'source_type' => 'event', 'policy_digest' => source.policy_version.digest,
      'provenance' => source.attributes.slice('account_id', 'policy_version_id', 'ticket_id', 'actor_id', 'rule_key',
                                             'correlation_key', 'evidence').merge('detected_at' => source.detected_at.iso8601(6)) }
  end
end
