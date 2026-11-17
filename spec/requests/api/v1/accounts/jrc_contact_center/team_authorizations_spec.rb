require 'rails_helper'

RSpec.describe 'Call Center inheritance through native teams', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let!(:headers) { actor.create_new_auth_token }
  let(:actor_link) { account.account_users.find_by!(user: actor) }
  let(:role) { create(:custom_role, account: account, permissions: JrcContactCenter::ModulePolicy::PERMISSIONS) }
  let(:recipient) { create(:user, account: account) }
  let(:team) { create(:team, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/access_authorizations/teams" }
  let(:native) { "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members" }
  let(:service) { JrcContactCenter::AccessAuthorization.new(context: { account: account, account_user: actor_link, user: actor }) }
  let(:grant) { service.grant_for(team) }
  let(:revision) { service.revision(team, grant) }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    actor_link.update!(custom_role: role)
  end

  it 'persists team rights without activating pending users or adding queue participation' do
    team.add_members([recipient.id])
    attributes = { authorization: { allowed: ['jrc_contact_center_publish'] }, expected_revision: revision }
    patch "#{base}/#{team.id}", headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:ok)
    expect(JrcContactCenter::AccessGrant.find_by!(team: team).allowed).to eq(['jrc_contact_center_publish'])
    member = account.account_users.find_by!(user: recipient)
    policy = JrcContactCenter::ModulePolicy.new({ account: account, account_user: member, user: recipient }, :contact_center)
    expect(policy.effective_permissions).to eq([])
    expect(JrcContactCenter::QueueMembership.where(account_user: member)).to be_empty
  end

  it 'denies granting team capabilities above actor authority' do
    role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_administer])
    attributes = { authorization: { allowed: ['jrc_contact_center_publish'] }, expected_revision: revision }
    patch "#{base}/#{team.id}", headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::AccessGrant.exists?(team: team)).to be(false)
  end

  it 'blocks activation and individual-denial fields on a team' do
    attributes = { authorization: { eligible: true, denied: ['jrc_contact_center_publish'] }, expected_revision: revision }
    patch "#{base}/#{team.id}", headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::AccessGrant.exists?(team: team)).to be(false)
  end

  it 'detects a membership change before accepting a stale team permission form' do
    old = revision
    team.add_members([recipient.id])
    attributes = { authorization: { allowed: [] }, expected_revision: old }
    patch "#{base}/#{team.id}", headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:conflict)
  end

  it 'prevents adding a pending recipient to a privileged team above actor authority' do
    JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: ['jrc_contact_center_publish'])
    role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_administer])
    post native, headers: headers, params: { user_ids: [recipient.id] }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(team.team_members.where(user: recipient)).to be_empty
  end

  it 'preserves native membership creation without granting eligibility or creating users' do
    role.update!(permissions: [])
    recipient
    expect do
      post native, headers: headers, params: { user_ids: [recipient.id] }, as: :json
    end.not_to change(User, :count)
    expect(response).to have_http_status(:ok)
    expect(team.team_members.where(user: recipient)).to exist
    expect(JrcContactCenter::AccessGrant.where(account_user: recipient.account_users)).to be_empty
  end

  it 'permits authorized native membership and lets removal revoke the inherited right' do
    member = account.account_users.find_by!(user: recipient)
    JrcContactCenter::AccessGrant.create!(account: account, account_user: member, eligible: true)
    JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: ['jrc_contact_center_publish'])
    post native, headers: headers, params: { user_ids: [recipient.id] }, as: :json
    expect(response).to have_http_status(:ok)
    context = { account: account, account_user: member, user: recipient }
    expect(JrcContactCenter::ModulePolicy.new(context, :contact_center).publish?).to be(true)
    delete native, headers: headers, params: { user_ids: [recipient.id] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(JrcContactCenter::ModulePolicy.new(context, :contact_center).publish?).to be(false)
  end

  it 'denies a foreign native user without adding a membership' do
    foreign = create(:user, account: create(:account))
    post native, headers: headers, params: { user_ids: [foreign.id] }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(team.team_members.where(user: foreign)).to be_empty
  end

  it 'does not return a foreign team through the new permission API' do
    foreign = create(:team, account: create(:account))
    get "#{base}/#{foreign.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end
end
