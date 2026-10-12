# No provider is installed in production. A name or client-uploaded PDF is not company-signature evidence.
class JrcApprovals::SignatureEvidence
  class << self
    attr_accessor :verifier

    def call(contract)
      return { 'state' => 'pending_provider', 'evidence_digest' => nil } unless verifier

      result = verifier.call(contract)
      if result.is_a?(Hash)
        data = result.stringify_keys
        valid = data.keys.sort == %w[evidence_digest state] && %w[verified pending invalid].include?(data['state']) &&
          (data['state'] != 'verified' || (data['evidence_digest'].is_a?(String) && data['evidence_digest'].match?(/\A[a-f0-9]{64}\z/)))
        return data if valid
      end
      { 'state' => 'invalid', 'evidence_digest' => nil }
    end
  end
end
