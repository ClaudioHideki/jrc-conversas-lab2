require 'rails_helper'

RSpec.describe 'DocuSign Connect inbox', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:secret) { 'synthetic-connect-secret-for-tests-only-1234' }
  let(:integration) do
    account.enable_features!('jrc_crm')
    attributes = { environment: 'demo', integration_key: SecureRandom.uuid, impersonated_user_id: SecureRandom.uuid,
                   external_account_id: SecureRandom.uuid, enabled: true,
                   private_key: OpenSSL::PKey::RSA.new(2048).to_pem, connect_hmac_keys: [secret] }
    JrcBackoffice::SignatureConfiguration.new(account: account, actor: admin).save!(expected_revision: 0, attributes: attributes)
  end
  let(:url) { "/webhooks/docusign/#{integration.public_id}" }
  let(:envelope_id) { SecureRandom.uuid }
  let(:payload) do
    { event: 'envelope-completed', apiVersion: 'v2.1', generatedDateTime: Time.current.iso8601,
      data: { accountId: integration.external_account_id, envelopeId: envelope_id,
              envelopeSummary: { emailSubject: 'PRIVATE SYNTHETIC SUBJECT', recipients: { signers: [{ email: 'private@example.test' }] } } } }
  end
  let(:raw) { payload.to_json }
  let(:signature) { Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', secret, raw)) }
  let(:headers) { { 'Content-Type' => 'application/json', 'X-Docusign-Signature-1' => signature } }

  it 'durably receives an authenticated event without declaring it processed or changing a contract' do
    expect { post url, params: raw, headers: headers }.to change(JrcBackoffice::SignatureNotification, :count).by(1)
    expect(response).to have_http_status(:accepted)
    record = JrcBackoffice::SignatureNotification.last
    expect(record).to have_attributes(account_id: account.id, state: 'received', envelope_id: envelope_id)
    expect(integration.reload.connect_checked_at).to be_present
    expect(integration.delivery_ready?).to be(false)
    expect(JrcCrm::AuditEvent.find_by!(event_type: 'signature_connect_checked', resource_id: integration.id).actor_type).to eq('Provider')
    expect(JrcCrm::Contract.where(account: account, signature_status: 'signed')).not_to exist
  end

  it 'encrypts the original event and exposes no payload or envelope identifiers in its generic JSON' do
    post url, params: raw, headers: headers
    record = JrcBackoffice::SignatureNotification.last
    expect(record.payload).to eq(payload.deep_stringify_keys)
    expect(record.encrypted_payload).not_to include('private@example.test', 'PRIVATE SYNTHETIC SUBJECT')
    expect(record.as_json.to_s).not_to include('encrypted_payload', 'private@example.test', envelope_id)
  end

  it 'deduplicates retries of exactly the same authenticated event' do
    post url, params: raw, headers: headers
    expect { post url, params: raw, headers: headers }.not_to change(JrcBackoffice::SignatureNotification, :count)
    expect(response).to have_http_status(:accepted)
    expect(JrcCrm::AuditEvent.where(event_type: 'signature_connect_checked', resource_id: integration.id).count).to eq(1)
  end

  it 'rejects tampering with the original bytes' do
    expect { post url, params: "#{raw} ", headers: headers }.not_to change(JrcBackoffice::SignatureNotification, :count)
    expect(response).to have_http_status(:unauthorized)
    expect(integration.reload.connect_checked_at).to be_nil
  end

  it 'rejects a valid HMAC whose provider account differs from the configured account' do
    payload[:data][:accountId] = SecureRandom.uuid
    expect { post url, params: raw, headers: headers }.not_to change(JrcBackoffice::SignatureNotification, :count)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'cannot use another integration callback URL with the original account secret' do
    other_account = create(:account)
    other_admin = create(:user, account: other_account, role: :administrator)
    other_account.enable_features!('jrc_crm')
    attributes = { environment: 'demo', integration_key: SecureRandom.uuid, impersonated_user_id: SecureRandom.uuid,
                   external_account_id: SecureRandom.uuid, enabled: true, private_key: OpenSSL::PKey::RSA.new(2048).to_pem,
                   connect_hmac_keys: ['other-synthetic-connect-secret-123456'] }
    other = JrcBackoffice::SignatureConfiguration.new(account: other_account, actor: other_admin)
                                                 .save!(expected_revision: 0, attributes: attributes)
    post "/webhooks/docusign/#{other.public_id}", params: raw, headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(other.reload.connect_checked_at).to be_nil
    expect(JrcBackoffice::SignatureNotification.where(account_id: other_account.id)).not_to exist
  end

  it 'rejects a missing signature and a missing integration identically' do
    expect do
      post url, params: raw, headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
      post "/webhooks/docusign/#{SecureRandom.uuid}", params: raw, headers: headers
      expect(response).to have_http_status(:unauthorized)
    end.not_to(change { JrcBackoffice::SignatureNotification.order(:id).pluck(:id) })
  end

  it 'preserves receipt on the original connection when the default is disabled for new sends' do
    old = integration.connection
    JrcBackoffice::SignatureConfiguration.new(account: account, actor: admin).save!(attributes: { enabled: false }, expected_revision: 1)
    post url, params: raw, headers: headers
    expect(response).to have_http_status(:accepted)
    expect(JrcBackoffice::SignatureNotification.last.connection_id).to eq(old.id)
    expect(integration.reload.connect_checked_at).to be_nil
    expect(integration.delivery_ready?).to be(false)
  end

  it 'rejects a connection that was disabled at creation despite a matching HMAC' do
    integration
    updated = JrcBackoffice::SignatureConfiguration.new(account: account, actor: admin)
                                                   .save!(attributes: { enabled: false }, expected_revision: 1)
    expect do
      post "/webhooks/docusign/#{updated.connection.public_id}", params: raw, headers: headers
    end.not_to(change { JrcBackoffice::SignatureNotification.order(:id).pluck(:id) })
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects account feature revocation after configuration' do
    integration
    account.disable_features!('jrc_crm')
    expect do
      post url, params: raw, headers: headers
    end.not_to(change { JrcBackoffice::SignatureNotification.order(:id).pluck(:id) })
    expect(response).to have_http_status(:unauthorized)
  end

  it 'keeps a historical event bound to its original account, environment and secret after changing the default' do
    old = integration.connection
    attributes = { environment: 'production', external_account_id: SecureRandom.uuid,
                   connect_hmac_keys: ['rotated-synthetic-connect-key-123456789'] }
    updated = JrcBackoffice::SignatureConfiguration.new(account: account, actor: admin).save!(expected_revision: 1, attributes: attributes)
    post url, params: raw, headers: headers
    expect(response).to have_http_status(:accepted)
    expect(JrcBackoffice::SignatureNotification.last.connection).to have_attributes(id: old.id, environment: 'demo',
                                                                                    external_account_id: payload[:data][:accountId])
    post "/webhooks/docusign/#{updated.connection.public_id}", params: raw, headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(updated.reload.connect_checked_at).to be_nil
  end

  it 'rejects invalid JSON with a matching signature' do
    invalid = '{"event":'
    invalid_signature = Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', secret, invalid))
    expect do
      post url, params: invalid, headers: headers.merge('X-Docusign-Signature-1' => invalid_signature)
    end.not_to(change { JrcBackoffice::SignatureNotification.order(:id).pluck(:id) })
    expect(response).to have_http_status(:unauthorized)
  end

  it 'limits request size before parsing or logging the body' do
    expect do
      post url, params: 'x' * (2.megabytes + 1), headers: headers
    end.not_to(change { JrcBackoffice::SignatureNotification.order(:id).pluck(:id) })
    expect(response).to have_http_status(:payload_too_large)
  end

  it 'filters the entire Connect payload in action instrumentation' do
    captured = []
    subscription = ActiveSupport::Notifications.subscribe('start_processing.action_controller') { |*args| captured << args.last[:params] }
    begin
      post url, params: raw, headers: headers
    ensure
      ActiveSupport::Notifications.unsubscribe(subscription)
    end
    expect(response).to have_http_status(:accepted)
    expect(captured).not_to be_empty
    expect(captured.to_json).not_to include('private@example.test', 'PRIVATE SYNTHETIC SUBJECT', integration.external_account_id)
    expect(captured.last['data']).to eq('[FILTERED]')
    expect(captured.last.dig('docusign', 'data')).to eq('[FILTERED]')
  end

  it 'does not decrypt notification evidence under another tenant context' do
    post url, params: raw, headers: headers
    record = JrcBackoffice::SignatureNotification.last
    record.account_id = create(:account).id
    expect { record.payload }.to raise_error(JrcBackoffice::Signatures::ProviderError, 'CREDENTIAL_UNAVAILABLE')
  end

  it 'refuses an empty POST without changing connection state or persisting a notification' do
    expect do
      post url, params: '', headers: { 'Content-Type' => 'application/json' }
    end.not_to(change { JrcBackoffice::SignatureNotification.order(:id).pluck(:id) })
    expect(response).to have_http_status(:unauthorized)
    expect(integration.reload.connect_checked_at).to be_nil
  end
end
