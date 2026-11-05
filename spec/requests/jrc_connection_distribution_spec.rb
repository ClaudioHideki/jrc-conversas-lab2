require 'rails_helper'

RSpec.describe 'Broker inbox distribution API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:team) { create(:team, account: account, allow_auto_assign: true) }
  let(:url) { "/api/v1/accounts/#{account.id}/jrc_broker/inboxes/#{inbox.id}/distribution" }
  let(:input) { { enabled: true, mode: 'priority', team_ids: [team.id], max_open: 4 } }

  around { |example| with_modified_env(JRC_BROKER_ENABLED: 'true') { example.run } }
  before do
    account.enable_features!('jrc_broker')
    JrcBrokerIntegration.create!(account: account, broker_origin: 'https://broker.example.test', organization_id: SecureRandom.uuid,
                                 destination_revision: 1, encrypted_control_key: 'synthetic-not-used')
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid)
  end

  it 'saves offline without calling the Broker and returns only same-account eligible teams' do
    foreign = create(:team, account: create(:account))
    expect(JrcBroker::Client).not_to receive(:new)
    put url, headers: admin.create_new_auth_token, params: input, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('policy')).to include('mode' => 'priority', 'team_ids' => [team.id])
    get url, headers: admin.create_new_auth_token
    expect(response.parsed_body.fetch('teams').pluck('id')).to eq([team.id])
    expect(response.parsed_body.to_json).not_to include(foreign.name)
    get url.sub('/distribution', '/distribution-history'), headers: admin.create_new_auth_token
    expect(response.parsed_body.fetch('data').first).to include('user_id' => admin.id, 'previous_policy' => {})
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'denies an agent for configuration and audit reads as well as writes' do
    get url, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    put url, headers: agent.create_new_auth_token, params: input, as: :json
    expect(response).to have_http_status(:forbidden)
    get url.sub('/distribution', '/distribution-history'), headers: agent.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    expect(JrcHumanAssignmentPolicyEvent.where(account_id: account.id)).to be_empty
  end

  it 'round trips central visibility and individual capacity without exposing credentials or calling the Broker' do
    create(:inbox_member, inbox: inbox, user: agent)
    expect(JrcBroker::Client).not_to receive(:new)
    policy = input.merge(visibility: 'assigned_only', supervisor_ids: [agent.id], agent_limits: { agent.id.to_s => 2 })
    put url, headers: admin.create_new_auth_token, params: policy, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['policy']).to include('visibility' => 'assigned_only', 'supervisor_ids' => [agent.id],
                                                      'agent_limits' => { agent.id.to_s => 2 })
    get url, headers: admin.create_new_auth_token
    expect(response.parsed_body['agents']).to include(include('id' => agent.id, 'name' => agent.name, 'active' => 0))
    expect(response.body).not_to include('synthetic-not-used')
    # An older client may omit the additive settings; it must not downgrade privacy.
    put url, headers: admin.create_new_auth_token, params: input, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['policy']['visibility']).to eq('assigned_only')
  end

  it 'rejects a foreign inbox even for a shared administrator' do
    foreign = create(:account)
    create(:account_user, account: foreign, user: admin, role: :administrator)
    foreign_inbox = create(:channel_api, account: foreign).inbox
    get url.sub("/inboxes/#{inbox.id}/", "/inboxes/#{foreign_inbox.id}/"), headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects invalid modes, capacities, duplicate teams and unavailable teams atomically' do
    blocked = create(:team, account: account, allow_auto_assign: false)
    [input.merge(mode: 'unknown'), input.merge(max_open: 0), input.merge(max_open: 101),
     input.merge(team_ids: [team.id, team.id]), input.merge(team_ids: [blocked.id]),
     input.merge(mode: 'direct', team_ids: [])].each do |body|
      put url, headers: admin.create_new_auth_token, params: body, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(JrcHumanAssignmentPolicyEvent.where(account_id: account.id)).to be_empty
    expect(account.reload.custom_attributes['jrc_human_assignment']).to be_nil
  end

  it 'does not accept unexpected control fields or query parameters' do
    put url, headers: admin.create_new_auth_token, params: input.merge(actor_id: agent.id), as: :json
    expect(response).to have_http_status(:bad_request)
    get "#{url}?token=synthetic-not-a-credential", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:bad_request)
  end

  it 'paginates all distribution changes with a stable inbox-scoped cursor' do
    51.times { JrcHumanAssignmentPolicyEvent.create!(account: account, inbox: inbox, user: admin, previous_policy: {}, next_policy: input) }
    get url.sub('/distribution', '/distribution-history'), headers: admin.create_new_auth_token
    first = response.parsed_body
    expect(first['data'].size).to eq(50)
    expect(first['next_cursor']).to be_present
    get url.sub('/distribution', '/distribution-history'), headers: admin.create_new_auth_token, params: { before: first['next_cursor'] }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['data'].size).to eq(1)
    expect(response.parsed_body['data'].first['id']).not_to be_in(first['data'].pluck('id'))
  end
end
