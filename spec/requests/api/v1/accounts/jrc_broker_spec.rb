require 'rails_helper'

RSpec.describe 'JRC Broker account control', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:connection_id) { SecureRandom.uuid }
  let(:instance_id) { SecureRandom.uuid }
  let(:organization_id) { SecureRandom.uuid }
  let(:prefix) { "/api/v1/accounts/#{account.id}/jrc_broker" }
  let(:inbox_url) { "#{prefix}/inboxes/#{inbox.id}" }
  let(:remote) { 'https://broker.example.test/v1/integrations/chatwoot/control' }
  let(:health) do
    { integrationId: connection_id, inboxId: inbox.id, instanceId: instance_id, integrationStatus: 'READY', instanceStatus: 'DISCONNECTED',
      transportStatus: 'UNVERIFIED', identityStatus: 'UNVERIFIED', identityApproved: true, identityRevision: 2, observedNumberSuffix: nil,
      checkedAt: Time.current.iso8601, callbackVerifiedAt: nil, lastSuccessfulInboundAt: nil, lastSuccessfulOutboundAt: nil,
      lastError: nil, allowedActions: %w[status pair disconnect manage] }
  end

  around do |example|
    with_modified_env(JRC_BROKER_ENABLED: 'true', JRC_BROKER_ALLOWED_ORIGINS: 'https://broker.example.test',
                      JRC_BROKER_CREDENTIAL_KEY: Base64.strict_encode64('k' * 32), FRONTEND_URL: 'https://chatwoot.example.test') { example.run }
  end

  before do
    account.enable_features!('jrc_broker')
    encrypted = JrcBroker::Configuration.credential_store.encrypt(account_id: account.id, token: 'synthetic-control')
    JrcBrokerIntegration.create!(account: account, broker_origin: 'https://broker.example.test', organization_id: organization_id,
                                 destination_revision: 1, encrypted_control_key: encrypted)
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: connection_id, instance_id: instance_id)
    stub_request(:get, "#{remote}/context").with(headers: { 'X-JRC-API-Key' => 'synthetic-control' }).to_return(status: 200, body: {
      organizationId: organization_id, accountId: account.id, chatwootOrigin: 'https://chatwoot.example.test', destinationRevision: 1, capabilities: {}
    }.to_json)
    stub_request(:get, "#{remote}/connections/#{connection_id}/status").to_return(status: 200, body: health.to_json)
  end

  it 'reads history progress only for the member inbox and discards secrets from the remote response' do
    member = create(:inbox_member, inbox: inbox, user: agent)
    payload = { schemaVersion: 2, organizationId: organization_id, channelId: SecureRandom.uuid,
                integrationId: connection_id, accountId: account.id, inboxId: inbox.id, destinationRevision: 1, run: nil,
                private_payload: 'SYNTHETIC_NEVER_EXPOSE' }
    stub_request(:get, "#{remote}/connections/#{connection_id}/history-sync/v2/progress").to_return(status: 200, body: payload.to_json)
    headers = agent.create_new_auth_token
    get "#{inbox_url}/history-sync", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('schemaVersion' => 2, 'inboxId' => inbox.id, 'run' => nil)
    expect(response.body).not_to include('SYNTHETIC_NEVER_EXPOSE', 'synthetic-control')
    stub_request(:get, "#{remote}/connections/#{connection_id}/history-sync/v2/progress")
      .to_return(status: 200, body: payload.merge(inboxId: inbox.id + 1).to_json)
    get "#{inbox_url}/history-sync", headers: headers
    expect(response).not_to have_http_status(:ok)
    member.destroy!
    get "#{inbox_url}/history-sync", headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it 'audits reconnection, expiry and identity mismatch once without retaining the pairing code' do
    headers = admin.create_new_auth_token.merge('Idempotency-Key' => 'synthetic-audit-intent')
    operation_id = SecureRandom.uuid
    stub_request(:post, "#{remote}/connections/#{connection_id}/pair").to_return(status: 200, body: {
      operationId: operation_id, instance: { id: instance_id },
      action: { type: 'PAIRING_CODE', code: 'NEVER-RETAIN', expiresAt: 1.minute.from_now.iso8601 }
    }.to_json)
    post "#{inbox_url}/pair", headers: headers, params: {}, as: :json
    expect(response).to have_http_status(:ok)
    expect(JrcBrokerConnectionEvent.where(account: account).pluck(:event_type)).to include('RECONNECT_REQUESTED')
    travel 2.minutes do
      2.times { get "#{inbox_url}/status", headers: headers }
    end
    expect(JrcBrokerConnectionEvent.where(account: account, event_type: 'QR_EXPIRED').count).to eq(1)
    stub_request(:get, "#{remote}/connections/#{connection_id}/status")
      .to_return(status: 200, body: health.merge(identityStatus: 'CONFIRMATION_REQUIRED').to_json)
    2.times { get "#{inbox_url}/status", headers: headers }
    expect(JrcBrokerConnectionEvent.where(account: account, event_type: 'NUMBER_MISMATCH').count).to eq(1)
    expect(JrcBrokerConnectionEvent.where(account: account).to_json).not_to include('NEVER-RETAIN', 'synthetic-control')
  end

  it 'records a confirmed connection transition once with the attempt actor and real provider timestamps only' do
    headers = admin.create_new_auth_token
    get "#{inbox_url}/status", headers: headers
    stub_request(:get, "#{remote}/connections/#{connection_id}/status").to_return(status: 200, body: health.merge(
      instanceStatus: 'CONNECTED', identityStatus: 'CONFIRMED', phoneNumber: '+5521988882000',
      connectedAt: '2026-11-02T11:45:00Z', lastSyncAt: nil
    ).to_json)
    2.times { get "#{inbox_url}/status", headers: headers }
    expect(response.parsed_body).to include('phoneNumber' => '+5521988882000', 'connectedAt' => '2026-11-02T11:45:00Z', 'lastSyncAt' => nil)
    expect(JrcBrokerConnectionEvent.where(account: account, event_type: 'CONNECTED').count).to eq(1)
  end

  it 'returns a typed invalid-response error for a malformed observed timestamp and preserves cached health' do
    headers = admin.create_new_auth_token
    get "#{inbox_url}/status", headers: headers
    previous = JrcBrokerInboxBinding.find_by!(inbox: inbox).connection_state.deep_dup
    stub_request(:get, "#{remote}/connections/#{connection_id}/status")
      .to_return(status: 200, body: health.merge(checkedAt: { invalid: 'timestamp' }).to_json)

    get "#{inbox_url}/status", headers: headers

    expect(response).to have_http_status(:bad_gateway)
    expect(response.parsed_body).to eq('code' => 'JRC_BROKER_INVALID_RESPONSE')
    expect(JrcBrokerInboxBinding.find_by!(inbox: inbox).connection_state).to eq(previous)
  end

  it 'adopts an existing API inbox idempotently without creating another inbox' do
    JrcBrokerInboxBinding.where(account: account).delete_all
    headers = admin.create_new_auth_token
    2.times do
      expect do
        post "#{prefix}/adopt", headers: headers, params: { integrationId: connection_id }, as: :json
      end.not_to change(Inbox, :count)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['inboxId']).to eq(inbox.id)
    end
    expect(JrcBrokerInboxBinding.where(account: account).count).to eq(1)
  end

  it 'rejects adoption by agents and never adopts an inbox belonging to another account' do
    post "#{prefix}/adopt", headers: agent.create_new_auth_token, params: { integrationId: connection_id }, as: :json
    expect(response).to have_http_status(:forbidden)
    other_inbox = create(:channel_api).inbox
    stub_request(:get, "#{remote}/connections/#{connection_id}/status").to_return(status: 200, body: health.merge(inboxId: other_inbox.id).to_json)
    post "#{prefix}/adopt", headers: admin.create_new_auth_token, params: { integrationId: connection_id }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcBrokerInboxBinding.find_by(inbox: other_inbox)).to be_nil
  end

  it 'preserves an existing binding and rejects an unready remote connection' do
    original = JrcBrokerInboxBinding.find_by!(inbox: inbox)
    other_id = SecureRandom.uuid
    stub_request(:get, "#{remote}/connections/#{other_id}/status")
      .to_return(status: 200, body: health.merge(integrationId: other_id).to_json)
    post "#{prefix}/adopt", headers: admin.create_new_auth_token, params: { integrationId: other_id }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(original.reload.integration_id).to eq(connection_id)
    stub_request(:get, "#{remote}/connections/#{connection_id}/status")
      .to_return(status: 200, body: health.merge(integrationStatus: 'DISABLED').to_json)
    post "#{prefix}/adopt", headers: admin.create_new_auth_token, params: { integrationId: connection_id }, as: :json
    expect(response).to have_http_status(:bad_gateway)
    expect(original.reload.integration_id).to eq(connection_id)
  end

  it 'rejects another account before calling the Broker and blocks the feature when disabled' do
    stranger = create(:user, account: create(:account), role: :administrator)
    get "#{inbox_url}/status", headers: stranger.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    expect(a_request(:get, "#{remote}/context")).not_to have_been_made
    with_modified_env(JRC_BROKER_ENABLED: 'false') do
      get "#{inbox_url}/status", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'requires a pairing grant as well as membership and removes authority on membership removal' do
    headers = agent.create_new_auth_token.merge('Idempotency-Key' => 'synthetic-pair-intent')
    post "#{inbox_url}/pair", headers: headers, params: {}, as: :json
    expect(response).to have_http_status(:forbidden)
    member = create(:inbox_member, inbox: inbox, user: agent)
    post "#{inbox_url}/pair", headers: headers, params: {}, as: :json
    expect(response).to have_http_status(:forbidden)
    JrcBrokerInboxGrant.create!(account: account, inbox: inbox, user: agent, can_pair: true)
    result = { instance: { id: instance_id, status: 'CONNECTING' }, action: { type: 'NONE', reason: 'CONNECTION_PENDING' } }
    stub = stub_request(:post, "#{remote}/connections/#{connection_id}/pair")
           .with(headers: { 'X-JRC-External-Actor' => agent.id.to_s }).to_return(status: 200, body: result.to_json)
    post "#{inbox_url}/pair", headers: headers, params: {}, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to eq('no-store')
    expect(response.body).not_to include('synthetic-control')
    member.destroy!
    post "#{inbox_url}/pair", headers: headers, params: {}, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(stub).to have_been_requested.once
  end

  it 'reads only durable pairing progress for an authorized inbox member without exposing QR data' do
    create(:inbox_member, inbox: inbox, user: agent)
    JrcBrokerInboxGrant.create!(account: account, inbox: inbox, user: agent, can_pair: true)
    operation_id = SecureRandom.uuid
    stub = stub_request(:get, "#{remote}/connections/#{connection_id}/pair-operations/#{operation_id}")
           .with(headers: { 'X-JRC-External-Actor' => agent.id.to_s })
           .to_return(status: 200, body: { operationId: operation_id, state: 'PENDING', instanceStatus: 'CONNECTING',
                                           reconciliationRequired: false, lastError: nil, updatedAt: Time.current.iso8601,
                                           action: nil, providerSecret: 'NEVER-EXPOSE' }.to_json)

    get "#{inbox_url}/pair-operations/#{operation_id}", headers: agent.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('operationId' => operation_id, 'state' => 'PENDING', 'reconciliationRequired' => false)
    expect(response.headers['Cache-Control']).to eq('no-store')
    expect(response.body).not_to include('NEVER-EXPOSE', 'synthetic-control')
    expect(stub).to have_been_requested.once
  end

  it 'does not release pairing progress when the grant is revoked during the Broker request' do
    create(:inbox_member, inbox: inbox, user: agent)
    grant = JrcBrokerInboxGrant.create!(account: account, inbox: inbox, user: agent, can_pair: true)
    operation_id = SecureRandom.uuid
    stub_request(:get, "#{remote}/connections/#{connection_id}/pair-operations/#{operation_id}").to_return do
      grant.destroy!
      { status: 200, body: { operationId: operation_id, state: 'SUCCEEDED', instanceStatus: 'CONNECTING',
                             reconciliationRequired: false, lastError: nil, updatedAt: Time.current.iso8601,
                             action: { type: 'PAIRING_CODE', code: 'NEVER-EXPOSE',
                                       expiresAt: 30.seconds.from_now.iso8601 } }.to_json }
    end

    get "#{inbox_url}/pair-operations/#{operation_id}", headers: agent.create_new_auth_token

    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include('SUCCEEDED', 'NEVER-EXPOSE')
  end

  [:admin, :agent].each do |role|
    [:removed, :integration_replaced, :instance_replaced].each do |change|
      it "does not release pairing progress to #{role} when the binding is #{change} during the Broker request" do
        actor = public_send(role)
        create(:inbox_member, inbox: inbox, user: actor)
        JrcBrokerInboxGrant.create!(account: account, inbox: inbox, user: actor, can_pair: true)
        operation_id = SecureRandom.uuid
        stub_request(:get, "#{remote}/connections/#{connection_id}/pair-operations/#{operation_id}").to_return do
          bindings = JrcBrokerInboxBinding.where(account: account, inbox: inbox)
          case change
          when :removed then bindings.delete_all
          when :integration_replaced then bindings.update_all(integration_id: SecureRandom.uuid)
          when :instance_replaced then bindings.update_all(instance_id: SecureRandom.uuid)
          end
          { status: 200, body: { operationId: operation_id, state: 'SUCCEEDED', reconciliationRequired: false,
                                action: { type: 'PAIRING_CODE', code: 'NEVER-EXPOSE',
                                          expiresAt: 30.seconds.from_now.iso8601 } }.to_json }
        end

        get "#{inbox_url}/pair-operations/#{operation_id}", headers: actor.create_new_auth_token

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body).to eq('code' => 'JRC_BROKER_FORBIDDEN')
        expect(response.headers['Cache-Control']).to eq('no-store')
        expect(response.body).not_to include('SUCCEEDED', 'NEVER-EXPOSE')
      end
    end
  end

  it 'does not expose admin actions to an inbox member or allow a first or changed identity' do
    create(:inbox_member, inbox: inbox, user: agent)
    JrcBrokerInboxGrant.create!(account: account, inbox: inbox, user: agent, can_pair: true)
    headers = agent.create_new_auth_token.merge('Idempotency-Key' => 'synthetic-pair-intent')
    get "#{inbox_url}/status", headers: headers
    expect(response.parsed_body['allowedActions']).to eq(%w[status pair])
    post "#{inbox_url}/disconnect", headers: headers, params: {}, as: :json
    expect(response).to have_http_status(:forbidden)
    [health.merge(identityApproved: false), health.merge(identityStatus: 'CONFIRMATION_REQUIRED')].each do |value|
      stub_request(:get, "#{remote}/connections/#{connection_id}/status").to_return(status: 200, body: value.to_json)
      post "#{inbox_url}/pair", headers: headers, params: {}, as: :json
      expect(response).to have_http_status(:forbidden)
    end
    expect(a_request(:post, "#{remote}/connections/#{connection_id}/pair")).not_to have_been_made
  end

  it 'rejects IDs and actors from request bodies, missing idempotency and a foreign inbox' do
    post "#{inbox_url}/pair", headers: admin.create_new_auth_token, params: {}, as: :json
    expect(response).to have_http_status(:bad_request)
    post "#{inbox_url}/pair", headers: admin.create_new_auth_token.merge('Idempotency-Key' => 'synthetic-intent'),
                              params: { organizationId: SecureRandom.uuid, actor: 'administrator' }, as: :json
    expect(response).to have_http_status(:bad_request)
    other_inbox = create(:inbox)
    get "#{prefix}/inboxes/#{other_inbox.id}/status", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    expect(a_request(:get, "#{remote}/context")).not_to have_been_made
  end

  it 'fails closed on revoked remote credentials without including the remote body' do
    stub_request(:get, "#{remote}/context").to_return(status: 403, body: 'private remote secret')
    get "#{inbox_url}/status", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include('private remote secret', 'synthetic-control')
  end

  it 'requires CSRF for cookie authentication even when an unverified token header is supplied' do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    allow(DeviseTokenAuth).to receive(:enable_standard_devise_support).and_return(true)
    sign_in admin
    [{}, { 'access-token' => 'invalid', 'client' => 'invalid' }].each do |headers|
      post "#{inbox_url}/pair", headers: headers.merge('Idempotency-Key' => 'synthetic-intent'), params: {}, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['code']).to eq('JRC_BROKER_CSRF_REQUIRED')
    end
    expect(a_request(:get, "#{remote}/context")).not_to have_been_made
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  it 'does not release a pairing code when inbox membership is removed during the remote call' do
    member = create(:inbox_member, inbox: inbox, user: agent)
    JrcBrokerInboxGrant.create!(account: account, inbox: inbox, user: agent, can_pair: true)
    stub_request(:post, "#{remote}/connections/#{connection_id}/pair").to_return do
      member.destroy!
      { status: 200, body: { instance: { id: instance_id }, action: { type: 'PAIRING_CODE', code: 'SYNTHETIC',
                                                                      expiresAt: 30.seconds.from_now.iso8601 } }.to_json }
    end
    post "#{inbox_url}/pair", headers: agent.create_new_auth_token.merge('Idempotency-Key' => 'synthetic-intent'), params: {}, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include('SYNTHETIC')
  end

  it 'lets an admin grant and revoke only current inbox members without changing the remote channel' do
    member = create(:inbox_member, inbox: inbox, user: agent)
    headers = admin.create_new_auth_token
    put "#{inbox_url}/grants", headers: headers, params: { userIds: [agent.id] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['data']).to include(include('user_id' => agent.id, 'can_pair' => true))
    put "#{inbox_url}/grants", headers: agent.create_new_auth_token, params: { userIds: [] }, as: :json
    expect(response).to have_http_status(:forbidden)
    put "#{inbox_url}/grants", headers: headers, params: { userIds: [] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(JrcBrokerInboxGrant.exists?(inbox_id: inbox.id)).to be(false)
    member.destroy!
    put "#{inbox_url}/grants", headers: headers, params: { userIds: [agent.id] }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(a_request(:get, "#{remote}/context")).not_to have_been_made
  end

  it 'does not release a pairing code if its explicit grant is revoked during the remote request' do
    create(:inbox_member, inbox: inbox, user: agent)
    grant = JrcBrokerInboxGrant.create!(account: account, inbox: inbox, user: agent, can_pair: true)
    stub_request(:post, "#{remote}/connections/#{connection_id}/pair").to_return do
      grant.destroy!
      { status: 200, body: { instance: { id: instance_id }, action: { type: 'PAIRING_CODE', code: 'SYNTHETIC',
                                                                  expiresAt: 30.seconds.from_now.iso8601 } }.to_json }
    end
    post "#{inbox_url}/pair", headers: agent.create_new_auth_token.merge('Idempotency-Key' => 'synthetic-intent'), params: {}, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include('SYNTHETIC')
    expect(InboxMember.exists?(inbox_id: inbox.id, user_id: agent.id)).to be(true)
  end

  it 'binds only a completed operation whose READY inbox and identifiers belong to this account' do
    operation_id = SecureRandom.uuid
    result = { operationId: operation_id, state: 'SUCCEEDED', stage: 'DONE', instanceId: instance_id,
               integrationId: connection_id, inboxId: inbox.id, lastError: nil }
    JrcBrokerInboxBinding.where(inbox_id: inbox.id).destroy_all
    stub_request(:get, "#{remote}/onboarding/#{operation_id}").to_return(status: 200, body: result.to_json)
    stub_request(:get, "#{remote}/connections/#{connection_id}/status").to_return(status: 200,
                                                                                  body: health.merge(integrationStatus: 'FAILED').to_json)
    get "#{prefix}/onboarding/#{operation_id}", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:bad_gateway)
    expect(JrcBrokerInboxBinding.exists?(inbox_id: inbox.id)).to be(false)
    stub_request(:get, "#{remote}/connections/#{connection_id}/status").to_return(status: 200, body: health.to_json)
    get "#{prefix}/onboarding/#{operation_id}", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(JrcBrokerInboxBinding.find_by!(inbox_id: inbox.id).integration_id).to eq(connection_id)
    expect(Inbox.where(id: inbox.id).count).to eq(1)
  end

  it 'assigns account members through the Broker only for administrators' do
    headers = admin.create_new_auth_token.merge('Idempotency-Key' => 'synthetic-members')
    stub = stub_request(:put, "#{remote}/connections/#{connection_id}/agents")
           .with(body: { agentIds: [agent.id] }.to_json, headers: { 'X-JRC-External-Actor' => admin.id.to_s })
           .to_return(status: 200, body: { ok: true }.to_json)
    put "#{inbox_url}/agents", headers: headers, params: { agentIds: [agent.id] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(stub).to have_been_requested.once
    put "#{inbox_url}/agents", headers: agent.create_new_auth_token.merge('Idempotency-Key' => 'synthetic-members'),
                               params: { agentIds: [agent.id] }, as: :json
    expect(response).to have_http_status(:forbidden)
    put "#{inbox_url}/agents", headers: headers, params: { agentIds: [create(:user).id] }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(stub).to have_been_requested.once
  end

  it 'keeps an agent membership scoped to its inbox' do
    second = create(:channel_api, account: account).inbox
    second_connection = SecureRandom.uuid
    second_instance = SecureRandom.uuid
    JrcBrokerInboxBinding.create!(account: account, inbox: second, integration_id: second_connection, instance_id: second_instance)
    create(:inbox_member, inbox: inbox, user: agent)
    JrcBrokerInboxGrant.create!(account: account, inbox: inbox, user: agent, can_pair: true)
    stub_request(:get, "#{remote}/connections/#{second_connection}/status")
      .to_return(status: 200, body: health.merge(inboxId: second.id, integrationId: second_connection, instanceId: second_instance).to_json)
    headers = agent.create_new_auth_token.merge('Idempotency-Key' => 'synthetic-second-inbox')
    get "#{inbox_url}/status", headers: headers
    expect(response.parsed_body['allowedActions']).to include('pair')
    get "#{prefix}/inboxes/#{second.id}/status", headers: headers
    expect(response).to have_http_status(:forbidden)
    post "#{prefix}/inboxes/#{second.id}/pair", headers: headers, params: {}, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(a_request(:post, "#{remote}/connections/#{second_connection}/pair")).not_to have_been_made
  end

  it 'records a disconnect failure without changing the persisted distribution' do
    headers = admin.create_new_auth_token.merge('Idempotency-Key' => 'synthetic-disconnect-failure')
    stub_request(:post, "#{remote}/connections/#{connection_id}/disconnect").to_return(status: 503, body: { code: 'ENGINE_UNAVAILABLE' }.to_json)
    post "#{inbox_url}/disconnect", headers: headers, params: {}, as: :json
    expect(response).to have_http_status(:bad_gateway)
    expect(JrcBrokerConnectionEvent.where(account: account).pluck(:event_type)).to include('DISCONNECT_REQUESTED', 'SESSION_FAILED')
  end

  it 'audits explicit pairing permission changes atomically with before and after' do
    create(:inbox_member, inbox: inbox, user: agent)
    put "#{inbox_url}/grants", headers: admin.create_new_auth_token, params: { userIds: [agent.id] }, as: :json
    expect(response).to have_http_status(:ok)
    event = JrcBrokerConnectionEvent.where(account: account, event_type: 'PERMISSIONS_CHANGED').last!
    expect(event.user_id).to eq(admin.id)
    expect(event.metadata).to include('previous_user_ids' => [], 'next_user_ids' => [agent.id])
  end

  it 'audits observed session failure codes without retaining untrusted provider error text' do
    headers = admin.create_new_auth_token
    stub_request(:get, "#{remote}/connections/#{connection_id}/status")
      .to_return(status: 200, body: health.merge(instanceStatus: 'ERROR', lastError: 'ENGINE_RECONNECT_FAILED').to_json)
    2.times { get "#{inbox_url}/status", headers: headers }
    expect(JrcBrokerConnectionEvent.where(account: account, event_type: 'SESSION_FAILED').last!.metadata['error_code']).to eq('ENGINE_RECONNECT_FAILED')
    stub_request(:get, "#{remote}/connections/#{connection_id}/status")
      .to_return(status: 200, body: health.merge(instanceStatus: 'ERROR', lastError: 'secret=NEVER-RETAIN-ERROR').to_json)
    2.times { get "#{inbox_url}/status", headers: headers }
    expect(JrcBrokerConnectionEvent.where(account: account, event_type: 'SESSION_FAILED').count).to eq(2)
    expect(JrcBrokerInboxBinding.find_by!(inbox: inbox).connection_state.to_json).not_to include('NEVER-RETAIN-ERROR')
  end
end
