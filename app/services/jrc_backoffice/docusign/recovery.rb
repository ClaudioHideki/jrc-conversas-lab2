# Read-only recovery after an ambiguous send. An empty result is inconclusive:
# DocuSign keeps transaction IDs for seven days. Never create another envelope.
class JrcBackoffice::Docusign::Recovery
  def initialize(client:)
    @client = client
  end

  def call(transaction_id:)
    row = unique_result!(@client.envelopes_for_transaction(transaction_id))
    return { found: false, state: 'unknown' } unless row

    id = row['envelopeId']
    invalid! unless id.is_a?(String) && id.match?(JrcBackoffice::SignatureIntegration::UUID)
    envelope = @client.envelope(id)
    invalid! unless envelope['envelopeId'].to_s.casecmp?(id) && envelope['transactionId'].to_s.casecmp?(transaction_id)

    { found: true, external_id: id, state: JrcBackoffice::Docusign::Adapter::STATES.fetch(envelope['status'], 'unknown'),
      provider_state: envelope['status'] }
  end

  private

  def unique_result!(result)
    rows = result['envelopes']
    invalid! unless rows.is_a?(Array) && rows.length <= 1 && result['nextUri'].blank?
    verify_result_count!(result, rows.length)
    invalid! unless rows.all?(Hash)

    rows.first
  end

  def verify_result_count!(result, count)
    return unless result.key?('totalSetSize')

    invalid! if Integer(result['totalSetSize'].to_s, 10) != count
  rescue ArgumentError
    invalid!
  end

  def invalid!
    raise JrcBackoffice::Signatures::ProviderError.new(code: 'PROVIDER_RESPONSE_INVALID')
  end
end
