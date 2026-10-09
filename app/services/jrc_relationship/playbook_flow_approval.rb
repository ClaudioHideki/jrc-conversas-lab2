class JrcRelationship::PlaybookFlowApproval
  PURPOSE = 'relationship-playbook-flow'.freeze

  def self.issue(reference)
    return unless reference.published_playbook? && reference.playbook.steps.include?(reference.step)

    expires_at = Time.current + reference.policy.definition.fetch('approval_ttl_seconds').seconds
    payload = binding(reference).merge('expires_at' => expires_at.iso8601(6))
    { 'approval_token' => verifier.generate(payload, purpose: PURPOSE, expires_at: expires_at),
      'approval_expires_at' => payload.fetch('expires_at') }
  end

  def self.verify!(reference, token)
    value = verifier.verified(token.to_s, purpose: PURPOSE)
    raise ArgumentError, 'playbook_flow_approval_invalid_or_expired' unless value.is_a?(Hash)
    raise ArgumentError, 'playbook_flow_approval_binding_changed' unless value.except('expires_at') == binding(reference)
    raise ArgumentError, 'playbook_flow_approval_expired' unless Time.iso8601(value.fetch('expires_at')) > Time.current

    value
  end

  def self.binding(reference)
    { 'payload_digest' => reference.payload_digest, 'scope' => reference.scope, 'source_key' => reference.source_key,
      'flow_id' => reference.flow.id, 'flow_version' => reference.flow.lock_version,
      'playbook_id' => reference.playbook&.id, 'playbook_version' => reference.playbook&.version }
  end

  def self.verifier
    Rails.application.message_verifier(PURPOSE)
  end
end
