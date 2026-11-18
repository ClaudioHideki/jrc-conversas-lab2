require 'rails_helper'

RSpec.describe 'Call Center private pause justification API', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:headers) { actor.create_new_auth_token }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/agent_state" }
  let(:catalog) { JrcContactCenter::PauseCatalog.new(account: account) }
  let(:entry) do
    { 'code' => 'synthetic_private', 'name' => 'SYNTHETIC private', 'category' => 'SYNTHETIC', 'active' => true,
      'default_minutes' => 30, 'unit_ids' => [], 'custom_role_ids' => [], 'justification_required' => true }
  end
  let(:payload) do
    { agent_state: { state: 'paused', reason_code: entry.fetch('code'), command_id: SecureRandom.uuid, expected_state_version: '0' } }
  end

  before do
    account.enable_features!('jrc_contact_center', 'audit_logs')
    catalog.update!({ 'enforced' => true, 'entries' => [entry] }, expected_revision: catalog.revision, activation_confirmed: true)
  end

  it 'rejects a missing required justification and leaves the database and native availability unchanged' do
    previous = member.reload.availability
    patch endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('pause_justification_required')
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
    expect(member.reload.availability).to eq(previous)
  end

  { boolean: false, integer: 42, array: [], object: {}, oversized: 'x' * 1001, blank: '  ' }.each do |kind, invalid|
    it "does not silently filter malformed or blank private input #{kind}" do
      patch endpoint, headers: headers, params: payload.deep_merge(agent_state: { justification: invalid }), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
    end
  end

  it 'persists private text, reloads it through the self API and preserves exactly-once receipt behavior' do
    request = payload.deep_merge(agent_state: { justification: 'SYNTHETIC API private text' })
    patch endpoint, headers: headers, params: request, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
    version = response.parsed_body.dig('item', 'state_version')
    get endpoint, headers: headers
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.parsed_body.dig('item', 'pause_definition', 'justification')).to eq('SYNTHETIC API private text')
    patch endpoint, headers: headers, params: request, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('item', 'state_version')).to eq(version)
    expect(JrcContactCenter::AgentStateEvent.where(account: account).count).to eq(1)
    changed = request.deep_merge(agent_state: { justification: 'SYNTHETIC changed private text' })
    patch endpoint, headers: headers, params: changed, as: :json
    expect(response).to have_http_status(:conflict)
    expect(JrcContactCenter::AgentStateEvent.where(account: account).count).to eq(1)
  end

  it 'does not use account or member IDs in a request to record a pause for another account' do
    other = create(:account)
    patch "/api/v1/accounts/#{other.id}/jrc_contact_center/agent_state", headers: headers,
          params: payload.deep_merge(agent_state: { justification: 'SYNTHETIC denied', account_user_id: member.id }), as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::AgentStateEvent.where(account: [account, other])).to be_empty
  end
end
