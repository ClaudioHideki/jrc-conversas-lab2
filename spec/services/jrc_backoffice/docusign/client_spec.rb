require 'rails_helper'

# The provider HTTP responses below are simulated. They do not prove external
# DocuSign authorization, consent, envelope delivery or Connect homologation.
RSpec.describe JrcBackoffice::Docusign::Client do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:private_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:integration) do
    credentials = { 'private_key' => private_key.to_pem, 'connect_hmac_keys' => ['synthetic-connect-key-for-tests-only-1234'] }
    JrcBackoffice::SignatureIntegration.create!(
      account: account, created_by: admin, environment: 'demo', credentials: credentials,
      integration_key: SecureRandom.uuid, impersonated_user_id: SecureRandom.uuid, external_account_id: SecureRandom.uuid,
      enabled: true, authorization_checked_at: Time.current, connect_checked_at: Time.current
    )
  end
  let(:client) { described_class.new(integration: integration) }
  let(:envelope_id) { SecureRandom.uuid }
  let(:transaction_id) { SecureRandom.uuid }
  let(:root) { "https://demo.docusign.net/restapi/v2.1/accounts/#{integration.external_account_id}" }
  let(:token_url) { 'https://account-d.docusign.com/oauth/token' }
  let(:info_url) { 'https://account-d.docusign.com/oauth/userinfo' }

  before do
    stub_request(:post, token_url).to_return(status: 200, body: { access_token: 'synthetic-token-only', expires_in: 3600 }.to_json)
    stub_request(:get, info_url).to_return(status: 200, body: {
      sub: integration.impersonated_user_id,
      accounts: [{ account_id: integration.external_account_id, base_uri: 'https://demo.docusign.net' }]
    }.to_json)
  end

  it 'signs a real RS256 JWT with the pinned user, integration, audience and scopes' do
    stub_request(:post, token_url).with do |request|
      values = URI.decode_www_form(request.body).to_h
      payload, = JWT.decode(values.fetch('assertion'), private_key.public_key, true, algorithm: 'RS256')
      expect(payload).to include('iss' => integration.integration_key, 'sub' => integration.impersonated_user_id,
                                 'aud' => 'account-d.docusign.com', 'scope' => 'signature impersonation')
      expect(payload.fetch('exp') - payload.fetch('iat')).to eq(3600)
      values.fetch('grant_type') == 'urn:ietf:params:oauth:grant-type:jwt-bearer'
    end.to_return(status: 200, body: { access_token: 'synthetic-token-only', expires_in: 3600 }.to_json)
    expect(client.check_authorization!).to be(true)
  end

  it 'refuses a service account not included in the authenticated user information' do
    stub_request(:get, info_url).to_return(status: 200, body: { sub: integration.impersonated_user_id, accounts: [] }.to_json)
    expect { client.check_authorization! }.to raise_error(JrcBackoffice::Docusign::Error, 'ACCOUNT_NOT_AUTHORIZED')
  end

  it 'refuses a base URI outside DocuSign before sending any credentials there' do
    stub_request(:get, info_url).to_return(status: 200, body: {
      sub: integration.impersonated_user_id,
      accounts: [{ account_id: integration.external_account_id, base_uri: 'https://demo.docusign.net.example.test' }]
    }.to_json)
    expect { client.check_authorization! }.to raise_error(JrcBackoffice::Docusign::Error, 'AUTHORIZATION_INVALID')
    expect(WebMock).not_to have_requested(:any, /docusign\.net\.example\.test/)
  end

  it 'does not label a connection without verified Connect as ready to send' do
    integration.update!(connect_checked_at: nil)
    expect { client.create_envelope(definition: {}, transaction_id: transaction_id) }
      .to raise_error(JrcBackoffice::Docusign::Error, 'CONNECTION_NOT_READY')
    expect(WebMock).not_to have_requested(:post, "#{root}/envelopes")
  end

  it 'requires both the provider envelope ID and sent confirmation, preserving the server transaction ID' do
    stub_request(:post, "#{root}/envelopes").with(body: { status: 'sent', transactionId: transaction_id }.to_json)
                                            .to_return(status: 201, body: { envelopeId: envelope_id, status: 'sent' }.to_json)
    expect(client.create_envelope(definition: {}, transaction_id: transaction_id)).to include('envelopeId' => envelope_id, 'status' => 'sent')
  end

  it 'treats a draft response as an ambiguous send, never sent success' do
    stub_request(:post, "#{root}/envelopes").to_return(status: 201, body: { envelopeId: envelope_id, status: 'created' }.to_json)
    expect { client.create_envelope(definition: {}, transaction_id: transaction_id) }
      .to raise_error(JrcBackoffice::Docusign::Error) { |error| expect(error.uncertain?).to be(true) }
  end

  it 'does not retry a timed-out envelope creation or expose tokens in the error' do
    stub_request(:post, "#{root}/envelopes").to_timeout
    expect { client.create_envelope(definition: {}, transaction_id: transaction_id) }
      .to raise_error(JrcBackoffice::Docusign::Error, 'PROVIDER_UNAVAILABLE') { |error| expect(error.uncertain?).to be(true) }
    expect(WebMock).to have_requested(:post, "#{root}/envelopes").once
  end

  it 'does not report a rejected request as uncertain provider success' do
    stub_request(:post, "#{root}/envelopes").to_return(status: 400, body: '{"errorCode":"INVALID_REQUEST","message":"sensitive synthetic detail"}')
    expect { client.create_envelope(definition: {}, transaction_id: transaction_id) }
      .to raise_error(JrcBackoffice::Docusign::Error, 'PROVIDER_REJECTED') { |error| expect(error.uncertain?).to be(false) }
  end

  it 'returns consent_required as a safe configuration error without leaking the response body' do
    stub_request(:post, token_url).to_return(status: 400, body: '{"error":"consent_required","detail":"sensitive synthetic detail"}')
    expect { client.check_authorization! }.to raise_error(JrcBackoffice::Docusign::Error, 'CONSENT_REQUIRED')
  end

  it 'uses the documented resend and void operations without assuming a signature occurred' do
    stub_request(:put, "#{root}/envelopes/#{envelope_id}?resend_envelope=true").with(body: '{}').to_return(status: 200, body: '')
    stub_request(:put, "#{root}/envelopes/#{envelope_id}").with(body: { status: 'voided', voidedReason: 'TESTE SINTÉTICO — cancelamento' }.to_json)
                                                          .to_return(status: 200, body: '')
    expect(client.resend(envelope_id)).to eq({})
    expect(client.cancel(envelope_id, reason: 'TESTE SINTÉTICO — cancelamento')).to eq({})
  end

  it 'refuses an HTML error page as a signed document' do
    stub_request(:get, "#{root}/envelopes/#{envelope_id}/documents/combined")
      .to_return(status: 200, body: '<html>synthetic provider failure</html>', headers: { 'Content-Type' => 'text/html' })
    expect { client.document(envelope_id, kind: 'combined') }.to raise_error(JrcBackoffice::Docusign::Error, 'PROVIDER_RESPONSE_INVALID')
  end

  it 'keeps credentials encrypted and binds the ciphertext to the internal account and revision' do
    expect(integration.encrypted_credentials).not_to include('BEGIN RSA PRIVATE KEY')
    expect(integration.as_json.keys).not_to include('encrypted_credentials', 'private_key')
    copied = integration.dup
    copied.account = create(:account)
    expect { copied.credentials }.to raise_error(JrcBackoffice::Signatures::ProviderError, 'CREDENTIAL_UNAVAILABLE')
  end

  it 'invalidates both provider checks after changing the integration identity' do
    integration.update!(external_account_id: SecureRandom.uuid)
    expect(integration.reload).to have_attributes(authorization_checked_at: nil, connect_checked_at: nil)
    expect(integration.delivery_ready?).to be(false)
  end
end
