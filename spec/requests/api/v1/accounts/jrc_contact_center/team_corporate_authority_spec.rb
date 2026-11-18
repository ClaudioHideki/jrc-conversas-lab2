require 'rails_helper'

RSpec.describe 'Native team membership and stored corporate authority', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:recipient) { create(:user, account: account) }
  let!(:headers) { actor.create_new_auth_token }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC issuer', relationship_type: 'internal') }
  let(:unit) { account.jrc_crm_business_units.create!(name: 'SYNTHETIC unit', code: 'A', operating_company: company) }
  let(:team) { create(:team, account: account) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members" }
  let(:role) { create(:custom_role, account: account, permissions: JrcContactCenter::ModulePolicy::PERMISSIONS + ['jrc_crm']) }
  let(:source) do
    account.jrc_crm_user_business_units.create!(user: recipient, team: team, scope: 'GROUP', structure_managed: true)
  end
  let(:coverage) { JrcCrm::CorporateCoverage.new(account: account, user: recipient) }

  before do
    account.enable_features!('jrc_contact_center', 'jrc_crm', 'custom_roles', 'audit_logs')
    account.account_users.find_by!(user: actor).update!(custom_role: role)
    unit
    account.jrc_crm_user_business_units.create!(user: actor, company: company, scope: 'COMPANY', structure_managed: true)
    team.add_members([recipient.id])
    account.jrc_crm_team_scopes.create!(team: team, scope: 'GROUP')
    source
    team.remove_members([recipient.id])
  end

  enabled_states = [true, false]
  %i[post patch].each do |verb|
    enabled_states.each do |contact_center|
      it "denies latent Group reactivation via #{verb}, with CC enabled #{contact_center}" do
        account.disable_features!('jrc_contact_center') unless contact_center
        expect(coverage).not_to be_group
        public_send(verb, endpoint, headers: headers, params: { user_ids: [recipient.id] }, as: :json)
        expect(response).to have_http_status(:unauthorized)
        expect(TeamMember.where(team_id: team.id)).to be_empty
        expect(source.reload).to be_active
        expect(coverage).not_to be_group
      end
    end

    it "permits a native Group administrator to authorize reinclusion via #{verb}" do
      account.jrc_crm_user_business_units.create!(user: actor, scope: 'GROUP', structure_managed: true)
      count = account.jrc_crm_user_business_units.count
      public_send(verb, endpoint, headers: headers, params: { user_ids: [recipient.id] }, as: :json)
      expect(response).to have_http_status(:ok)
      expect(team.team_members.where(user: recipient)).to exist
      expect(coverage).to be_group
      expect(account.jrc_crm_user_business_units.count).to eq(count)
      expect(JrcContactCenter::AccessGrant.where(account_user: recipient.account_users)).to be_empty
    end
  end

  it 'preserves pure removal without requiring Group or rewriting the stored corporate source' do
    team.add_members([recipient.id])
    delete endpoint, headers: headers, params: { user_ids: [recipient.id] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(TeamMember.where(team_id: team.id)).to be_empty
    expect(source.reload).to be_active
    expect(coverage).not_to be_group
  end

  it 'preserves no-op removal of a nonmember with dormant corporate and functional grants' do
    JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: ['jrc_contact_center_publish'])
    role.update!(permissions: [])
    delete endpoint, headers: headers, params: { user_ids: [recipient.id] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(TeamMember.where(team_id: team.id)).to be_empty
    expect(coverage).not_to be_group
  end

  it 'preserves removal by replacement while refusing an atomic replacement that adds latent coverage' do
    existing = create(:user, account: account)
    team.add_members([existing.id])
    patch endpoint, headers: headers, params: { user_ids: [recipient.id] }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(TeamMember.where(team_id: team.id).pluck(:user_id)).to eq([existing.id])
    patch endpoint, headers: headers, params: { user_ids: [] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(TeamMember.where(team_id: team.id)).to be_empty
  end

  it 'keeps an explicitly inactive corporate source inactive after native membership creation' do
    team.add_members([recipient.id])
    source.update!(active: false)
    team.remove_members([recipient.id])
    post endpoint, headers: headers, params: { user_ids: [recipient.id] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(source.reload).not_to be_active
    expect(coverage).not_to be_group
  end

  it 'rejects a foreign account route without modifying either corporate source or membership' do
    foreign = create(:team, account: create(:account))
    post "/api/v1/accounts/#{account.id}/teams/#{foreign.id}/team_members",
         headers: headers, params: { user_ids: [recipient.id] }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(foreign.team_members).to be_empty
    expect(source.reload).to be_active
  end

  it 'does not reactivate stored corporate authority through the legacy bootstrap path without business units' do
    unit.destroy!
    expect(JrcCrm::CorporateCoverage.new(account: account, user: actor)).not_to be_configured
    post endpoint, headers: headers, params: { user_ids: [recipient.id] }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(TeamMember.where(team_id: team.id)).to be_empty
    expect(coverage).not_to be_group
  end

  it 'preserves explicit Group administrative reinclusion even without configured business units' do
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'GROUP', structure_managed: true)
    unit.destroy!
    post endpoint, headers: headers, params: { user_ids: [recipient.id] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(TeamMember.where(team_id: team.id, user_id: recipient.id)).to exist
    expect(coverage).to be_group
  end
end
