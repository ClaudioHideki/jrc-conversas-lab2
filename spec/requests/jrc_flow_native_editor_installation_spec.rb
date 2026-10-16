require 'rails_helper'

RSpec.describe 'P9 new native editor and installation HTTP cases', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:organization) { SecureRandom.uuid }
  let(:root) { SecureRandom.uuid }
  let(:channel) { SecureRandom.uuid }
  let(:integration) { SecureRandom.uuid }
  let(:prefix) { "/api/v1/accounts/#{account.id}/jrc_flow_delegation" }
  let(:credential) { 't' * 43 }
  let(:session_token) { 's' * 43 }
  let(:grant_token) { 'g' * 43 }
  let(:installation_callback) { 'i' * 43 }
  let(:registration_callback) { SecureRandom.urlsafe_base64(32) }

  around { |example| with_modified_env(JRC_FLOWS_ENABLED: 'true', JRC_BROKER_ALLOWED_ORIGINS: 'https://broker.example.test', FRONTEND_URL: 'https://host.example.test') { example.run } }

  before do
    account.enable_features!('jrc_flows')
    create(:inbox_member, inbox: inbox, user: admin)
    @original_alfred = $alfred
    $alfred = ConnectionPool.new(size: 2, timeout: 1) { Redis.new(url: ENV.fetch('FLOW_TEST_REDIS_URL')) }
    $alfred.with(&:flushdb)
  end

  after do
    $alfred.shutdown(&:close)
    $alfred = @original_alfred
  end

  def registration
    @registration ||= begin
      row = JrcFlowNativeRegistration.create!(
        account: account, created_by: admin, account_user: AccountUser.find_by!(account: account, user: admin),
        broker_origin: 'https://broker.example.test', host_origin: 'https://host.example.test', organization_id: organization,
        challenge_id: SecureRandom.uuid, broker_registration_id: SecureRandom.uuid, broker_registration_revision: 1,
        credential_id: SecureRandom.uuid, credential_revision: 1, destination_revision: 2, account_credential_version: 3,
        tuple: { targets: [{ integrationId: integration, channelId: channel, inboxId: inbox.id, transport: 'CENTRAL_TRANSPORT', provider: nil }] },
        expires_at: 1.hour.from_now, credential_expires_at: 1.hour.from_now
      )
      row.update!(state: 'ACTIVE', callback_digest: Digest::SHA256.hexdigest(registration_callback),
                  encrypted_outbound_credential: seal(row.id, 'OUTBOUND', credential))

      row
    end
  end

  def seal(id, purpose, value)
    JrcFlows::NativeCredentialStore.for_application.encrypt(account_id: account.id, record_id: id, revision: 1, purpose: purpose, token: value)
  end

  def handle
    @handle ||= begin
      row = registration.session_handles.create!(
        account: account, user: admin, broker_session_id: SecureRandom.uuid, public_id: SecureRandom.uuid,
        nonce: SecureRandom.uuid, credential_revision: 1, registration_revision: registration.revision, expires_at: 3.minutes.from_now,
        inbox_ids: [inbox.id], scopes: %w[flow:read flow:edit flow:publish flow:bind], remote_close_pending: false
      )
      row.update!(encrypted_session_bearer: seal(row.id, 'SESSION_BEARER', session_token)); row
    end
  end

  def editor_path
    "#{prefix}/sessions/#{handle.public_id}/flows/#{root}"
  end

  def installation
    @installation ||= begin
      tuple = { accountId: account.id, destinationRevision: 2, accountCredentialVersion: 3, targets: registration.tuple.fetch('targets') }
      row = JrcFlowNativeInstallation.create!(
        account: account, created_by: admin, registration: registration, grant_id: SecureRandom.uuid,
        tuple: tuple, tuple_digest: Digest::SHA256.hexdigest(JSON.generate(tuple)), operation_nonce: SecureRandom.uuid,
        callback_digest: Digest::SHA256.hexdigest(installation_callback), encrypted_callback: '', operation_expires_at: 5.minutes.from_now
      )
      row.update!(encrypted_callback: seal(row.id, 'INSTALLATION_CALLBACK', installation_callback),
                  encrypted_transfer_nonce: seal(row.id, 'INSTALLATION_TRANSFER', 'n' * 43))

      row
    end
  end

  def installation_proof
    row = installation
    { audience: 'FLOW_INSTALLATION_CLAIM', grantId: row.grant_id, operationNonce: row.operation_nonce,
      proofNonce: SecureRandom.uuid, expectedGeneration: 1,
      registrationId: registration.broker_registration_id, registrationRevision: 1, credentialId: registration.credential_id, credentialRevision: 1,
      destinationRevision: 2, accountCredentialVersion: 3, accountId: account.id, tupleDigest: row.tuple_digest }
  end
  it 'forwards editor only through the actor-bound handle and never returns the session bearer' do
    path = editor_path
    stub_request(:get, "https://broker.example.test/v1/delegated-flows/#{root}").with(
      headers: { 'Authorization' => "Bearer #{session_token}" }
    ).to_return(
      status: 200, body: { id: root, name: 'Flow' }.to_json
    )
    get path, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(session_token)
    expect(response.headers['Cache-Control']).to eq('no-store')
  end

  it 'denies editor handle use by another current user of the same Account' do
    path = editor_path
    other = create(:user, account: account, role: :administrator)
    create(:inbox_member, inbox: inbox, user: other)
    get path, headers: other.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'rechecks actual write role after editor I/O and refuses the stale response' do
    path = editor_path
    stub_request(:put, "https://broker.example.test/v1/delegated-flows/#{root}").to_return do
      AccountUser.find_by!(account: account, user: admin).update!(role: :agent)
      { status: 200, body: { id: root, name: 'Changed' }.to_json }
    end
    put path, headers: admin.create_new_auth_token, params: { revision: 1 }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['code']).to eq('FLOW_CAPABILITY_NOT_GRANTED')
  end

  it 'rechecks actual Inbox membership after editor I/O' do
    path = editor_path
    stub_request(:get, "https://broker.example.test/v1/delegated-flows/#{root}").to_return do
      InboxMember.where(inbox: inbox, user: admin).delete_all
      { status: 200, body: { id: root, name: 'Flow' }.to_json }
    end
    get path, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
  end

  it 'authenticates the dedicated installation callback and fixes its exact proof nonce' do
    proof = installation_proof
    post '/api/v1/jrc_flow_native/installation-challenge', headers: { 'Authorization' => "Bearer #{installation_callback}" }, params: proof, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('authorized' => true)
    expect(installation.reload.proof_nonce).to eq(proof[:proofNonce])
    post '/api/v1/jrc_flow_native/installation-challenge', headers: { 'Authorization' => "Bearer #{installation_callback}" },
                                                           params: proof.merge(proofNonce: SecureRandom.uuid), as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects native registration and grant audiences at the installation proof endpoint' do
    proof = installation_proof
    [credential, grant_token, registration_callback].each do |wrong|
      post '/api/v1/jrc_flow_native/installation-challenge', headers: { 'Authorization' => "Bearer #{wrong}" }, params: proof, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  it 'stores claimed installation bearer encrypted and gives browser metadata only' do
    row = installation
    expiry = (29.days.from_now).iso8601
    stub_request(:post, "https://broker.example.test/v1/flow-delegations/native-installation-grants/#{row.grant_id}/claim").with(
      headers: { 'Authorization' => "Bearer #{credential}" }
    ).to_return(
      status: 200, body: { id: row.grant_id, token: grant_token, generation: 1, expiresAt: expiry,
                           credentialExpiresAt: registration.credential_expires_at.iso8601 }.to_json
    )
    post "#{prefix}/installations", headers: admin.create_new_auth_token, params: { grantId: row.grant_id, transferNonce: 'n' * 43 }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(grant_token)
    expect(row.reload.state).to eq('ACTIVE')
    expect(row.encrypted_grant).not_to include(grant_token)
  end

  it 'reduces installation locally before uncertain remote revoke and retains a reduce-only tombstone' do
    row = installation
    row.update!(state: 'ACTIVE', encrypted_grant: seal(row.id, 'INSTALLATION_GRANT', grant_token), expires_at: 29.days.from_now)
    handle
    stub_request(:delete, "https://broker.example.test/v1/flow-delegations/native-installations/#{row.grant_id}").to_timeout
    delete "#{prefix}/installations/#{row.grant_id}", headers: admin.create_new_auth_token, params: {}, as: :json
    expect(response).to have_http_status(:service_unavailable)
    expect(row.reload.state).to eq('REVOKED')

    expect(row.encrypted_grant).to be_nil
    expect(row.encrypted_revoke_bearer).not_to be_nil
    expect(row.remote_revoke_pending).to eq(true)
    expect(handle.reload.encrypted_session_bearer).to be_nil
    expect(registration.reload.state).to eq('REVOKED')
  end
end
