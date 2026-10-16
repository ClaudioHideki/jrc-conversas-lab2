require 'rails_helper'

RSpec.describe 'Flow native host installed HTTP boundary', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:organization) { SecureRandom.uuid }
  let(:credential_id) { SecureRandom.uuid }
  let(:prefix) { "/api/v1/accounts/#{account.id}/jrc_flow_delegation" }
  let(:broker) { 'https://broker.example.test/v1/flow-delegations' }
  let(:callback) { SecureRandom.urlsafe_base64(32) }
  let(:token) { 't' * 43 }
  let(:native_request) do
    { nonce: SecureRandom.uuid, externalActorId: admin.id.to_s, accountId: account.id, destinationRevision: 2, inboxIds: [inbox.id] }
  end
  let(:context) do
    { credential: { id: credential_id, revision: 1, expiresAt: (12.hours.from_now).iso8601, scopes: %w[flow:read flow:bind] },
      destination: { organizationId: organization, origin: 'https://host.example.test', accountId: account.id,
                     destinationRevision: 2, accountCredentialVersion: 3 },
      targets: [{ integrationId: SecureRandom.uuid, channelId: SecureRandom.uuid, accountId: account.id,
                  inboxId: inbox.id, transport: 'CENTRAL_TRANSPORT', provider: nil }], nextCursor: nil }
  end

  around do |example|
    with_modified_env(JRC_FLOWS_ENABLED: 'true', JRC_BROKER_ALLOWED_ORIGINS: 'https://broker.example.test', FRONTEND_URL: 'https://host.example.test') { example.run }
  end

  before do
    account.enable_features!('jrc_flows')
    create(:inbox_member, inbox: inbox, user: admin)
    # The actual host adapter is exercised against the isolated Redis process.
    @original_alfred = $alfred
    $alfred = ConnectionPool.new(size: 2, timeout: 1) { Redis.new(url: ENV.fetch('FLOW_TEST_REDIS_URL')) }
    $alfred.with(&:flushdb)
  end

  after do
    $alfred.shutdown(&:close)
    $alfred = @original_alfred
  end

  def active_registration(callback_token: callback)
    record = JrcFlowNativeRegistration.create!(
      account: account, created_by: admin, account_user: AccountUser.find_by!(account: account, user: admin),
      broker_origin: 'https://broker.example.test', host_origin: 'https://host.example.test', organization_id: organization,
      challenge_id: SecureRandom.uuid, broker_registration_id: SecureRandom.uuid, broker_registration_revision: 1,
      credential_id: credential_id, credential_revision: 1, destination_revision: 2, account_credential_version: 3,
      tuple: { targets: context[:targets].map do |target|
        target.except(:accountId)
      end }, expires_at: 1.hour.from_now, credential_expires_at: 1.hour.from_now
    )
    cipher = JrcFlows::NativeCredentialStore.for_application.encrypt(account_id: account.id, record_id: record.id, revision: 1, purpose: 'OUTBOUND',
                                                                     token: token)
    record.update!(state: 'ACTIVE', callback_digest: Digest::SHA256.hexdigest(callback_token), encrypted_outbound_credential: cipher)
    record
  end

  it 'authenticates the dedicated callback and applies live Inbox membership, expiry and revocation from PostgreSQL' do
    record = active_registration
    post '/api/v1/jrc_flow_native/introspect', headers: { 'Authorization' => "Bearer #{callback}" }, params: native_request, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('member' => true, 'role' => 'administrator', 'featureEnabled' => true)
    expect(response.headers['Cache-Control']).to eq('no-store')
    InboxMember.where(inbox: inbox, user: admin).delete_all
    post '/api/v1/jrc_flow_native/introspect', headers: { 'Authorization' => "Bearer #{callback}" }, params: native_request, as: :json
    expect(response.parsed_body).to include('member' => false)
    record.update!(expires_at: 1.second.ago)
    post '/api/v1/jrc_flow_native/introspect', headers: { 'Authorization' => "Bearer #{callback}" }, params: native_request, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects QR keys, browser actor injection and oversized bodies before granting authority' do
    post '/api/v1/jrc_flow_native/introspect', headers: { 'X-JRC-API-Key' => callback }, params: native_request, as: :json
    expect(response).to have_http_status(:forbidden)
    post "#{prefix}/sessions", headers: admin.create_new_auth_token,
                               params: { inboxIds: [inbox.id], scopes: ['flow:read'], externalActorId: 'other' }, as: :json
    expect(response).to have_http_status(:bad_request)
    post '/api/v1/jrc_flow_native/introspect', headers: { 'Authorization' => "Bearer #{callback}", 'CONTENT_TYPE' => 'application/json' },
                                               params: ' ' * 16_385
    expect(response).to have_http_status(:payload_too_large)
    expect(response.headers['Cache-Control']).to eq('no-store')
  end

  it 'configures through the real controller/client and stores only Account-purpose ciphertext' do
    stub_request(:get, "#{broker}/native-context?limit=25").with(headers: { 'Authorization' => "Bearer #{token}" }).to_return(status: 200,
                                                                                                                              body: context.to_json)
    put "#{prefix}/configuration", headers: admin.create_new_auth_token,
                                   params: { brokerOrigin: 'https://broker.example.test', nativeCredential: token }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('configured' => true)
    expect(response.body).not_to include(token)
    stored = JrcFlowNativeConfiguration.find_by!(account: account)
    expect(stored.encrypted_outbound_credential).not_to include(token)
    expect(stored.organization_id).to eq(organization)
    expect(JrcFlows::NativeCredentialStore.for_application.decrypt(
             account_id: account.id, record_id: account.id, revision: 1,
             purpose: 'CONFIGURATION_OUTBOUND', ciphertext: stored.encrypted_outbound_credential
           )).to eq(token)
  end

  it 'rechecks role after the remote configuration response and does not persist revoked authority' do
    stub_request(:get, "#{broker}/native-context?limit=25").to_return do
      AccountUser.find_by!(account: account, user: admin).update!(role: :agent)
      { status: 200, body: context.to_json }
    end
    put "#{prefix}/configuration", headers: admin.create_new_auth_token,
                                   params: { brokerOrigin: 'https://broker.example.test', nativeCredential: token }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['code']).to eq('FLOW_CAPABILITY_NOT_GRANTED')
    expect(JrcFlowNativeConfiguration.where(account: account)).not_to exist
  end

  it 'closes the exact persisted actor session after Inbox membership loss and retains its tombstone' do
    record = active_registration
    handle = record.session_handles.create!(
      account: account, user: admin, broker_session_id: SecureRandom.uuid,
      public_id: SecureRandom.uuid, nonce: SecureRandom.uuid, credential_revision: 1, expires_at: 3.minutes.from_now,
      encrypted_session_bearer: 'synthetic-cipher', remote_close_pending: false
    )
    InboxMember.where(inbox: inbox, user: admin).delete_all
    stub_request(:delete, "#{broker}/native-sessions/#{handle.broker_session_id}").with(
      headers: { 'Authorization' => "Bearer #{token}" },
      body: { externalActorId: admin.id.to_s, nonce: handle.nonce }.to_json
    ).to_return(status: 200, body: { revoked: true }.to_json)
    delete "#{prefix}/sessions/#{handle.public_id}", headers: admin.create_new_auth_token, params: {}, as: :json
    expect(response).to have_http_status(:ok)
    expect(handle.reload.closed_at).not_to be_nil
    expect(handle.encrypted_session_bearer).to be_nil
    expect(handle.remote_close_pending).to eq(false)
    expect(JrcFlowNativeSessionHandle.exists?(handle.id)).to eq(true)
  end

  it 'enforces tenant Inbox FKs and Account uniqueness on persisted Flow records' do
    record = active_registration
    # Build unrelated enterprise fixtures with the suite's standard cache;
    # the isolated Redis5 pool remains the real HTTP/rate-limit target.
    isolated_alfred = $alfred
    begin
      $alfred = @original_alfred
      foreign_inbox = create(:channel_api).inbox
    ensure
      $alfred = isolated_alfred
    end
    expect do
      JrcFlowNativeBinding.transaction(requires_new: true) do
        record.bindings.create!(account: account, inbox: foreign_inbox, integration_id: SecureRandom.uuid, channel_id: SecureRandom.uuid,
                                transport: 'CENTRAL_TRANSPORT', registration_revision: 1)
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    expect do
      JrcFlowNativeRegistration.transaction(requires_new: true) { active_registration(callback_token: SecureRandom.urlsafe_base64(32)) }
    end.to raise_error(ActiveRecord::RecordNotUnique, /jrc_flow_active_account_unique/)
  end
end
