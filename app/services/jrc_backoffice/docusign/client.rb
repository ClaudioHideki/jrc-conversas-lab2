class JrcBackoffice::Docusign::Client
  def initialize(integration:)
    @integration = integration
    @transport = JrcBackoffice::Docusign::Transport.new
    @session = JrcBackoffice::Docusign::OauthSession.new(integration: integration, transport: @transport)
  end

  def check_authorization!
    @session.authenticate!
  end

  def create_envelope(definition:, transaction_id:)
    raise JrcBackoffice::Docusign::Error.new(code: 'CONNECTION_NOT_READY') unless @integration.delivery_ready?

    uuid!(transaction_id)
    result = api(:post, 'envelopes', body: definition.merge('status' => 'sent', 'transactionId' => transaction_id))
    valid_id = result['envelopeId'].is_a?(String) && result['envelopeId'].match?(JrcBackoffice::SignatureIntegration::UUID)
    raise JrcBackoffice::Docusign::Error.new(code: 'SEND_NOT_CONFIRMED', uncertain: true) unless valid_id && result['status'] == 'sent'

    result
  end

  def envelope(id)
    api(:get, "envelopes/#{uuid!(id)}")
  end

  def envelopes_for_transaction(transaction_id)
    api(:get, "envelopes?transaction_ids=#{uuid!(transaction_id)}&count=2")
  end

  def recipients(id)
    api(:get, "envelopes/#{uuid!(id)}/recipients")
  end

  def documents(id)
    api(:get, "envelopes/#{uuid!(id)}/documents")
  end

  def resend(id)
    raise JrcBackoffice::Docusign::Error.new(code: 'CONNECTION_NOT_READY') unless @integration.delivery_ready?

    api(:put, "envelopes/#{uuid!(id)}?resend_envelope=true", body: {}, allow_empty: true)
  end

  def cancel(id, reason:)
    raise ArgumentError, 'Cancellation reason required' unless reason.is_a?(String) && reason.strip.length.between?(1, 1000)

    api(:put, "envelopes/#{uuid!(id)}", body: { status: 'voided', voidedReason: reason.strip }, allow_empty: true)
  end

  def document(id, kind:)
    raise ArgumentError, 'Unsupported signature document' unless %w[combined certificate].include?(kind)

    api(:get, "envelopes/#{uuid!(id)}/documents/#{kind}", raw: true)
  end

  private

  def api(method, path, body: nil, raw: false, allow_empty: false)
    headers = @session.headers
    url = "#{@session.base_uri}/restapi/v2.1/accounts/#{uuid!(@integration.external_account_id)}/#{path}"
    format = raw ? :pdf : :json
    format = :empty_json if allow_empty
    @transport.call(method: method, url: url, headers: headers, body: body&.to_json, format: format)
  end

  def uuid!(value)
    valid = value.is_a?(String) && value.match?(JrcBackoffice::SignatureIntegration::UUID)
    raise JrcBackoffice::Docusign::Error.new(code: 'PROVIDER_ID_INVALID') unless valid

    value
  end
end
