require 'rails_helper'

RSpec.describe 'Call Center administrative workflows', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: user) }
  let(:headers) { user.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center" }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, code: 'LOCAL', name: 'Local', kind: 'sac') }

  before { account.enable_features!('jrc_contact_center') }

  it 'reports saved configuration without claiming an online PABX or an applied operation' do
    get "#{base}/administration", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('provider')).to include('configured' => false, 'state' => 'pending_contract', 'last_sync_at' => nil)
  end

  it 'offers native team member options only to a native team administrator' do
    get "#{base}/administration/teams", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('can_manage')).to be(true)
    expect(response.parsed_body.fetch('agents')).to include('user_id' => user.id, 'name' => user.available_name)
    expect(response.parsed_body.fetch('agents').first.keys).to match_array(%w[user_id name])
  end

  it 'does not turn Call Center configure into native team administration' do
    role = CustomRole.create!(account: account, name: 'Local config', permissions: %w[jrc_contact_center_view jrc_contact_center_configure])
    member.update!(role: :agent, custom_role: role)
    get "#{base}/administration/teams", headers: headers
    expect(response.parsed_body.fetch('can_manage')).to be(false)
    expect(response.parsed_body).not_to have_key('agents')
    post "/api/v1/accounts/#{account.id}/teams", params: { team: { name: 'Denied team' } }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(account.teams).to be_empty
  end

  it 'uses native team membership without creating a distribution or supervision assignment' do
    team = create(:team, account: account)
    patch "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
          params: { user_ids: [user.id] }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(team.reload.members.pluck(:id)).to eq([user.id])
    expect(JrcContactCenter::QueueMembership.where(account: account)).to be_empty
  end

  it 'keeps native team member writes within the Account' do
    team = create(:team, account: account)
    foreign = create(:user, :contact_center_eligible, account: create(:account))
    patch "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
          params: { user_ids: [foreign.id] }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(team.reload.members).to be_empty
  end

  it 'preserves a non-voice queue contract while changing its local name' do
    queue = JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'CHAT', name: 'Chat', service_kind: 'whatsapp')
    patch "#{base}/queues/#{queue.id}", params: { queue: { name: 'Reviewed', service_kind: 'whatsapp' } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(queue.reload).to have_attributes(name: 'Reviewed', service_kind: 'whatsapp', strategy: 'provider')
  end

  it 'revalidates revoked permissions for writes using the same authentication token' do
    role = CustomRole.create!(account: account, name: 'Local config', permissions: %w[jrc_contact_center_view jrc_contact_center_configure])
    member.update!(role: :agent, custom_role: role)
    target = unit
    patch "#{base}/units/#{target.id}", params: { unit: { name: 'Allowed' } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    role.update!(permissions: ['jrc_contact_center_view'])
    patch "#{base}/units/#{target.id}", params: { unit: { name: 'Denied' } }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(target.reload.name).to eq('Allowed')
  end

  it 'does not expose or activate a native approval authority without its original eligibility' do
    account.enable_features!('jrc_approvals')
    role = CustomRole.create!(account: account, name: 'Approval entry', permissions: %w[jrc_contact_center_view jrc_contact_center_approve])
    member.update!(custom_role: role)
    get "#{base}/administration", headers: headers
    expect(response.parsed_body.fetch('cards').pluck('key')).to include('approvals')
    expect(response.parsed_body.fetch('native_links').fetch('approvals')).to be(false)
    expect(JrcCrm::UserBusinessUnit.where(account: account, user: user)).to be_empty
  end

  it 'offers the native role popup only when its feature and native role permit it' do
    account.enable_features!('custom_roles')
    get "#{base}/administration", headers: headers
    expect(response.parsed_body.fetch('native_links')).to include('permissions' => true, 'role_editor' => true)
    member.update!(role: :agent)
    get "#{base}/administration", headers: headers
    expect(response.parsed_body.fetch('native_links')).to include('permissions' => false, 'role_editor' => false)
  end

  it 'provides real authorized Account feature flags to the native permission editor' do
    account.enable_features!('custom_roles')
    get "/api/v1/accounts/#{account.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('id')).to eq(account.id)
    expect(response.parsed_body.fetch('features')).to include('jrc_contact_center' => true, 'custom_roles' => true)
  end

  context 'with a corporate business-unit boundary' do
    let(:company) { JrcCustomers::Company.create!(account: account, name: 'Issuer', relationship_type: 'internal', active: true) }
    let(:allowed_business_unit) { JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'A', code: 'A', active: true) }
    let(:denied_business_unit) { JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'B', code: 'B', active: true) }
    let(:denied_unit) do
      JrcContactCenter::Unit.create!(
        account: account, code: 'DENIED', name: 'Denied', kind: 'sac',
        settings: { issuer_company_id: company.id, business_unit_id: denied_business_unit.id }
      )
    end

    before do
      JrcCrm::UserBusinessUnit.create!(
        account: account, user: user, company: company, business_unit: allowed_business_unit,
        scope: 'BUSINESS_UNIT', active: true, structure_managed: true
      )
    end

    it 'does not expose account-wide native team editing or its agent options' do
      get "#{base}/administration/teams", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('can_manage')).to be(false)
      expect(response.parsed_body).not_to have_key('agents')
    end

    it 'does not offer account-wide native role editing under a restricted corporate scope' do
      account.enable_features!('custom_roles')
      get "#{base}/administration", headers: headers
      expect(response.parsed_body.fetch('native_links').fetch('role_editor')).to be(false)
    end

    it 'rejects queue creation and membership assignment in another business unit' do
      post "#{base}/queues", params: { queue: { name: 'Denied', code: 'DENIED', unit_id: denied_unit.id } }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      queue = JrcContactCenter::Queue.create!(account: account, unit: denied_unit, code: 'DENIED', name: 'Denied')
      post(
        "#{base}/queue_memberships",
        headers: headers,
        as: :json,
        params: { queue_membership: { queue_id: queue.id, account_user_id: member.id } }
      )
      expect(response).to have_http_status(:not_found)
      expect(queue.reload.memberships).to be_empty
    end

    it 'rejects a new operational unit linked outside corporate coverage' do
      post "#{base}/units", headers: headers, as: :json, params: {
        unit: { name: 'Denied', code: 'FORBIDDEN', kind: 'sac',
                settings: { issuer_company_id: company.id, business_unit_id: denied_business_unit.id } }
      }
      expect(response).to have_http_status(:unauthorized)
      expect(JrcContactCenter::Unit.where(account: account, code: 'FORBIDDEN')).to be_empty
    end
  end
end
