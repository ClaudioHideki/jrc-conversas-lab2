# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'JRC Contact Center access scope', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: agent) }
  let(:headers) { agent.create_new_auth_token }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, code: 'SAC', name: 'SAC', kind: 'sac') }
  let(:allowed_queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'Q1', name: 'Fila 1') }
  let(:hidden_queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'Q2', name: 'Fila 2') }

  before do
    account.enable_features!('jrc_contact_center')
    JrcContactCenter::QueueMembership.create!(account: account, queue: allowed_queue, account_user: member)
  end

  it 'limits ordinary agents to queues explicitly assigned to them' do
    allowed_case = JrcContactCenter::Case.create!(
      account: account, queue: allowed_queue, protocol: 'CC-ALLOW', channel: 'voice', category: 'general', summary: 'Visible'
    )
    JrcContactCenter::Case.create!(
      account: account, queue: hidden_queue, protocol: 'CC-HIDDEN', channel: 'voice', category: 'general', summary: 'Hidden'
    )

    get "/api/v1/accounts/#{account.id}/jrc_contact_center/cases", headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([allowed_case.id])
  end

  it 'rejects an ordinary agent writing an occurrence outside the assigned queues' do
    post "/api/v1/accounts/#{account.id}/jrc_contact_center/cases",
         params: { case: { queue_id: hidden_queue.id, category: 'general', summary: 'Denied' } }, headers: headers, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::Case.where(account: account)).to be_empty
  end

  it 'rejects an unassigned occurrence that would disappear from the agent scope' do
    post "/api/v1/accounts/#{account.id}/jrc_contact_center/cases",
         params: { case: { category: 'general', summary: 'No assignment' } }, headers: headers, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::Case.where(account: account)).to be_empty
  end

  it 'shows ordinary agents only calls assigned to them' do
    assigned_call = JrcContactCenter::CallSession.create!(
      account: account,
      current_unit: unit,
      current_queue: allowed_queue,
      provider: 'jrc_pabx',
      correlation_id: 'assigned-call',
      direction: 'inbound',
      status: 'connected',
      started_at: Time.current
    )
    JrcContactCenter::CallLeg.create!(
      account: account,
      call_session: assigned_call,
      queue: allowed_queue,
      account_user: member,
      direction: 'inbound',
      status: 'connected',
      started_at: Time.current
    )
    JrcContactCenter::CallSession.create!(
      account: account,
      current_unit: unit,
      current_queue: allowed_queue,
      provider: 'jrc_pabx',
      correlation_id: 'queue-only-call',
      direction: 'inbound',
      status: 'queued',
      started_at: Time.current
    )

    get "/api/v1/accounts/#{account.id}/jrc_contact_center/call_sessions",
        params: { assignee_type: 'all' }, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([assigned_call.id])
  end

  it 'allows administrators to list unassigned calls separately' do
    administrator = create(:user, account: account, role: :administrator)
    assigned_call = JrcContactCenter::CallSession.create!(
      account: account,
      current_unit: unit,
      current_queue: allowed_queue,
      provider: 'jrc_pabx',
      correlation_id: 'admin-assigned-call',
      direction: 'inbound',
      status: 'connected',
      started_at: Time.current
    )
    JrcContactCenter::CallLeg.create!(
      account: account,
      call_session: assigned_call,
      queue: allowed_queue,
      account_user: member,
      direction: 'inbound',
      status: 'connected',
      started_at: Time.current
    )
    unassigned_call = JrcContactCenter::CallSession.create!(
      account: account,
      current_unit: unit,
      current_queue: hidden_queue,
      provider: 'jrc_pabx',
      correlation_id: 'admin-unassigned-call',
      direction: 'inbound',
      status: 'queued',
      started_at: Time.current
    )

    get "/api/v1/accounts/#{account.id}/jrc_contact_center/call_sessions",
        params: { assignee_type: 'unassigned' },
        headers: administrator.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([unassigned_call.id])
  end

  it 'rejects a direct call lookup from another account' do
    other_account = create(:account)
    other_call = JrcContactCenter::CallSession.create!(
      account: other_account, provider: 'jrc_pabx', correlation_id: 'other-account-call',
      direction: 'inbound', status: 'queued', started_at: Time.current
    )

    get "/api/v1/accounts/#{account.id}/jrc_contact_center/call_sessions/#{other_call.id}", headers: headers, as: :json

    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(other_call.correlation_id)
  end

  it 'does not expose a teammate call through unassigned filters or direct lookup' do
    teammate = create(:user, account: account, role: :agent)
    teammate_call = JrcContactCenter::CallSession.create!(
      account: account, current_queue: allowed_queue, provider: 'jrc_pabx', correlation_id: 'teammate-call',
      direction: 'inbound', status: 'connected', started_at: Time.current
    )
    JrcContactCenter::CallLeg.create!(
      account: account, call_session: teammate_call, queue: allowed_queue,
      account_user: account.account_users.find_by!(user: teammate), direction: 'inbound',
      status: 'connected', started_at: Time.current
    )

    get "/api/v1/accounts/#{account.id}/jrc_contact_center/call_sessions",
        params: { assignee_type: 'unassigned' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to be_empty

    get "/api/v1/accounts/#{account.id}/jrc_contact_center/call_sessions/#{teammate_call.id}", headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
  end
end
