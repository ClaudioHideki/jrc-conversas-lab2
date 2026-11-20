require 'rails_helper'

RSpec.describe 'Call Center inactive team coverage keeps all other modules unchanged', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let!(:headers) { actor.create_new_auth_token }
  let(:manager) { account.account_users.find_by!(user: actor) }
  let(:recipient) { create(:user, :contact_center_eligible, account: account) }
  let(:member) { account.account_users.find_by!(user: recipient) }
  let(:team) { create(:team, account: account) }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC source issuer', relationship_type: 'internal') }
  let(:business) { account.jrc_crm_business_units.create!(operating_company: company, code: 'SOURCE', name: 'SYNTHETIC business') }
  let(:grant) { JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: ['jrc_contact_center_monitor']) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/access_authorizations/teams/#{team.id}" }
  let(:authority) { JrcContactCenter::AccessAuthorization.new(context: { account: account, account_user: manager, user: actor }) }
  let(:scope) { account.jrc_crm_user_business_units.find_by!(user: recipient, team: team) }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    manager.update!(custom_role: create(:custom_role, account: account, permissions: JrcContactCenter::ModulePolicy::PERMISSIONS))
    member.update!(custom_role: create(:custom_role, account: account, permissions: ['jrc_contact_center_view']))
    business
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'GROUP', structure_managed: true)
    team.add_members([recipient.id])
    account.jrc_crm_team_scopes.create!(team: team, scope: 'GROUP')
    account.jrc_crm_user_business_units.create!(user: recipient, team: team, scope: 'GROUP', structure_managed: true)
  end

  it 'suspends only Call Center inherited corporate coverage without changing native grants or CRM coverage' do
    original = scope.attributes
    patch endpoint, headers: headers, params: { authorization: { active: false }, expected_revision: authority.revision(team, grant) }, as: :json
    expect(response).to have_http_status(:ok)
    expect(JrcContactCenter::CorporateCoverage.new(account: account, user: recipient)).not_to be_group
    expect(JrcCrm::CorporateCoverage.new(account: account, user: recipient)).to be_group
    expect(scope.reload.attributes).to eq(original)
    expect(JrcContactCenter::CorporateCoverage.new(account: account, user: recipient)).to be_configured
    expect(JrcContactCenter::CorporateCoverage.new(account: account, user: recipient).unit_ids).to be_empty
  end

  it 'keeps direct corporate scope and another active team source when one source is inactive' do
    other = create(:team, account: account)
    other.add_members([recipient.id])
    account.jrc_crm_team_scopes.create!(team: other, scope: 'GROUP')
    account.jrc_crm_user_business_units.create!(user: recipient, team: other, scope: 'GROUP', structure_managed: true)
    JrcContactCenter::TeamState.create!(account: account, team: team, active: false)
    expect(JrcContactCenter::CorporateCoverage.new(account: account, user: recipient)).to be_group
    expect(scope.reload).to be_active
    expect(team.members).to include(recipient)
  end

  it 'checks all effective rights when reactivation widens coverage even if those rights already exist individually' do
    JrcContactCenter::TeamState.create!(account: account, team: team, active: false)
    JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(allowed: ['jrc_contact_center_monitor'])
    manager.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_administer])
    grant.update!(allowed: [])
    patch endpoint, headers: headers, params: { authorization: { active: true }, expected_revision: authority.revision(team, grant) }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::TeamState.find_by!(team: team)).not_to be_active
    expect(JrcContactCenter::CorporateCoverage.new(account: account, user: recipient)).not_to be_group
    expect(JrcCrm::CorporateCoverage.new(account: account, user: recipient)).to be_group
  end

  it 'does not allow an actor to restore its own suspended source as authorization for that operation' do
    team.add_members([actor.id])
    account.jrc_crm_user_business_units.where(user: actor, team_id: nil).destroy_all
    account.jrc_crm_user_business_units.create!(user: actor, team: team, scope: 'GROUP', structure_managed: true)
    JrcContactCenter::TeamState.create!(account: account, team: team, active: false)
    patch endpoint, headers: headers, params: { authorization: { active: true }, expected_revision: authority.revision(team, grant) }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::TeamState.find_by!(team: team)).not_to be_active
    expect(scope.reload).to be_active
  end
end
