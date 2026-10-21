# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'JRC Contact Center F1 operations', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:headers) { agent.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center" }

  it 'does not allow a local state mutation while the feature is disabled' do
    patch "#{base}/agent_state", headers: headers, as: :json,
                                 params: { agent_state: { state: 'available', command_id: 'test-1', expected_state_version: '0' } }

    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end

  it 'records the authenticated agent state without accepting a different actor' do
    account.enable_features!('jrc_contact_center')
    patch "#{base}/agent_state", headers: headers, as: :json,
                                 params: { agent_state: { state: 'available', command_id: 'test-1', expected_state_version: '0',
                                                          account_user_id: 999_999 } }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['item']).to include('state' => 'available', 'eligible' => false, 'provider_confirmed' => false)
    expect(JrcContactCenter::AgentStateEvent.find_by!(account: account).account_user.user_id).to eq(agent.id)
  end

  it 'rejects a pending provider command without creating a command or calling a gateway' do
    account.enable_features!('jrc_contact_center')
    post "#{base}/commands", headers: headers, as: :json,
                             params: { command: { action: 'originate', command_id: 'pending-1', parameters: { destination: '1001' } } }

    expect(response).to have_http_status(:not_implemented)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'does not expose supervisor or control desk data to a native agent' do
    account.enable_features!('jrc_contact_center')
    get "#{base}/supervisor", headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    get "#{base}/integrations/health", headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not mutate another account through the account URL' do
    foreign = create(:account)
    foreign.enable_features!('jrc_contact_center')
    patch "/api/v1/accounts/#{foreign.id}/jrc_contact_center/agent_state", headers: headers, as: :json,
                                                                           params: { agent_state: { state: 'available', command_id: 'foreign',
                                                                                                    expected_state_version: '0' } }

    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::AgentStateEvent.where(account: foreign)).to be_empty
  end

  it 'reprocesses only a verified failed event and enqueues the existing reconciler' do
    account.enable_features!('jrc_contact_center')
    admin = create(:user, account: account, role: :administrator)
    event = JrcContactCenter::EventIngestor.new(account: account).call(
      { schema_version: '1.0', event_id: 'reprocess-1', event_type: 'call.created', occurred_at: Time.current.iso8601,
        provider: 'jrc_pabx', correlation_id: 'reprocess-call' }, signature_verified: true
    ).record
    event.update!(status: 'failed', last_error: 'internal detail')

    expect do
      post "#{base}/events/#{event.id}/reprocess", headers: admin.create_new_auth_token, as: :json
    end.to have_enqueued_job(JrcContactCenter::EventReconcileJob).with(account.id, event.id)

    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body['item']).not_to include('payload', 'last_error')
    expect(event.reload).to have_attributes(status: 'pending', last_error: nil)
  end

  it 'does not reprocess an unverified event even for an administrator' do
    account.enable_features!('jrc_contact_center')
    admin = create(:user, account: account, role: :administrator)
    event = JrcContactCenter::EventIngestor.new(account: account).call(
      { schema_version: '1.0', event_id: 'unverified-1', event_type: 'call.created', occurred_at: Time.current.iso8601,
        provider: 'jrc_pabx', correlation_id: 'unverified-call' }
    ).record
    event.update!(status: 'failed')

    post "#{base}/events/#{event.id}/reprocess", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(event.reload.status).to eq('failed')
  end

  it 'does not let an agent control another agent call merely because both belong to the same queue' do
    account.enable_features!('jrc_contact_center')
    unit = JrcContactCenter::Unit.create!(account: account, code: 'SAC', name: 'SAC', kind: 'sac')
    queue = JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'Q', name: 'Queue')
    member = account.account_users.find_by!(user: agent)
    JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member)
    other_agent = create(:user, account: account, role: :agent)
    other_member = account.account_users.find_by!(user: other_agent)
    session = JrcContactCenter::CallSession.create!(account: account, correlation_id: 'peer-call', direction: 'inbound',
                                                    status: 'connected', started_at: 2.minutes.ago, answered_at: 1.minute.ago, current_queue: queue)
    session.legs.create!(account: account, account_user: other_member, direction: 'inbound', status: 'connected', started_at: session.started_at)

    post "#{base}/commands", headers: headers, as: :json,
                             params: { command: { action: 'transfer_blind', command_id: 'peer-transfer', call_session_id: session.id,
                                                  expected_state_version: session.lock_version, parameters: { destination: '1001' } } }

    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(session.correlation_id)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end
end
