require 'rails_helper'

RSpec.describe 'Call Center private pause options and supervisor scope', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:observer) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC pause privacy issuer', relationship_type: 'internal') }
  let(:business_units) do
    %w[A B].map do |code|
      JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: "SYNTHETIC privacy #{code}", code: code)
    end
  end
  let(:units) do
    business_units.map do |business|
      JrcContactCenter::Unit.create!(account: account, code: business.code, name: business.name, kind: 'sac',
                                     settings: { issuer_company_id: company.id, business_unit_id: business.id })
    end
  end
  let(:queues) do
    units.map do |unit|
      queue = JrcContactCenter::Queue.create!(account: account, unit: unit, name: unit.name, code: unit.code)
      JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member)
      queue
    end
  end
  let(:api) { "/api/v1/accounts/#{account.id}/jrc_contact_center" }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles')
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_supervise])
    account.account_users.find_by!(user: observer).update!(custom_role: role)
    JrcCrm::UserBusinessUnit.create!(account: account, user: observer, scope: 'BUSINESS_UNIT', company: company,
                                     business_unit: business_units.first, active: true, structure_managed: true)
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'GROUP', active: true, structure_managed: true)
    queues
    catalog = JrcContactCenter::PauseCatalog.new(account: account)
    reason = { 'code' => 'synthetic_b', 'name' => 'SYNTHETIC PRIVATE B NAME', 'category' => 'SYNTHETIC',
               'description' => 'SYNTHETIC PRIVATE B DESCRIPTION', 'active' => true, 'default_minutes' => 30,
               'unit_ids' => [units.last.id], 'custom_role_ids' => [] }
    catalog.update!({ 'enforced' => true, 'entries' => [reason] }, expected_revision: catalog.revision, activation_confirmed: true)
    JrcContactCenter::AgentStateManager.new(account: account, account_user: member).transition(
      state: 'paused', reason_code: 'synthetic_b', queue_id: queues.last.id, command_id: SecureRandom.uuid, expected_state_version: '0'
    )
  end

  it 'includes rich authorized pause data in the authenticated operator self response' do
    get "#{api}/agent_state", headers: actor.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('item', 'pause_definition', 'name')).to eq('SYNTHETIC PRIVATE B NAME')
    expect(response.parsed_body.dig('item', 'pause_catalog', 'entries').sole.fetch('name')).to eq('SYNTHETIC PRIVATE B NAME')
  end

  it 'does not copy private operator options or the Unit B snapshot into a Unit A supervisor response' do
    get "#{api}/supervisor", headers: observer.create_new_auth_token
    expect(response).to have_http_status(:ok)
    data = response.parsed_body.fetch('agents').sole
    expect(data.fetch('account_user_id')).to eq(member.id.to_s)
    expect(data.fetch('queues').map { |queue| queue.fetch('id') }).to eq([queues.first.id.to_s])
    expect(data).not_to have_key('pause_catalog')
    expect(data).not_to have_key('pause_definition')
    expect(data.fetch('reason_code')).to be_nil
    expect(response.body).not_to include('SYNTHETIC PRIVATE B NAME', 'SYNTHETIC PRIVATE B DESCRIPTION')
  end

  it 'does not use a caller-provided member id to return another operator private catalog' do
    get "#{api}/agent_state", headers: observer.create_new_auth_token, params: { account_user_id: member.id }
    expect(response).to have_http_status(:ok)
    expected = account.account_users.find_by!(user: observer).id.to_s
    expect(response.parsed_body.dig('item', 'account_user_id')).to eq(expected)
    expect(response.parsed_body.dig('item', 'pause_catalog')).to be_nil
    expect(response.body).not_to include('SYNTHETIC PRIVATE B NAME', 'SYNTHETIC PRIVATE B DESCRIPTION')
  end

  it 'removes the historical rich projection after the operator loses its Unit B corporate coverage' do
    JrcCrm::UserBusinessUnit.find_by!(account: account, user: actor, scope: 'GROUP').update!(
      scope: 'BUSINESS_UNIT', company: company, business_unit: business_units.first
    )
    get "#{api}/agent_state", headers: actor.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('item', 'pause_definition')).to be_nil
    expect(response.parsed_body.dig('item', 'pause_catalog', 'entries')).to be_empty
    expect(response.body).not_to include('SYNTHETIC PRIVATE B NAME', 'SYNTHETIC PRIVATE B DESCRIPTION')
  end

  it 'preserves authorized legacy reason visibility for a supervisor whose Group scope includes the current queue' do
    JrcCrm::UserBusinessUnit.find_by!(account: account, user: observer).update!(scope: 'GROUP', company: nil, business_unit: nil)
    get "#{api}/supervisor", headers: observer.create_new_auth_token
    expect(response).to have_http_status(:ok)
    data = response.parsed_body.fetch('agents').sole
    expect(data.fetch('reason_code')).to eq('synthetic_b')
    expect(data).not_to have_key('pause_catalog')
    expect(data).not_to have_key('pause_definition')
  end
end
