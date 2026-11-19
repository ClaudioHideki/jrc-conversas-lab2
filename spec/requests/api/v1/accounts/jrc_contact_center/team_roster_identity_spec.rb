require 'rails_helper'

RSpec.describe 'Native team roster identity and inherited authority', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:recipient) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: recipient) }
  let(:team) { create(:team, account: account) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members" }
  let(:headers) { actor.create_new_auth_token }
  let(:context) { { account: account, account_user: member, user: recipient } }
  let(:coverage) { JrcCrm::CorporateCoverage.new(account: account, user: recipient) }
  let(:source) do
    account.jrc_crm_user_business_units.create!(user: recipient, team: team, scope: 'GROUP', structure_managed: true)
  end

  before do
    account.enable_features!('jrc_contact_center', 'jrc_crm', 'custom_roles', 'audit_logs')
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'GROUP', structure_managed: true)
    member.update!(custom_role: create(:custom_role, account: account, permissions: []))
    team.add_members([recipient.id])
    account.jrc_crm_team_scopes.create!(team: team, scope: 'GROUP')
    source
    JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: %w[jrc_contact_center_view jrc_contact_center_operate])
  end

  it 'preserves the exact member and current inherited sources on a string-ID no-op replacement' do
    original = team.team_members.sole.id
    expect(JrcContactCenter::ModulePolicy.new(context, :contact_center)).to be_operate
    expect(coverage).to be_group
    patch endpoint, headers: headers, params: { user_ids: [recipient.id.to_s] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(team.team_members.reload.pluck(:id)).to eq([original])
    expect(JrcContactCenter::ModulePolicy.new(context, :contact_center)).to be_operate
    expect(coverage).to be_group
    expect(source.reload).to be_active
  end

  it 'keeps selected members while adding and removing different members in the same string-ID request' do
    removed = create(:user, account: account)
    added = create(:user, account: account)
    team.add_members([removed.id])
    original = team.team_members.find_by!(user: recipient).id
    patch endpoint, headers: headers, params: { user_ids: [recipient.id.to_s, added.id.to_s] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(team.team_members.reload.pluck(:user_id)).to contain_exactly(recipient.id, added.id)
    expect(team.team_members.find_by!(user: recipient).id).to eq(original)
    expect(JrcContactCenter::ModulePolicy.new(context, :contact_center)).to be_operate
    expect(coverage).to be_group
  end

  it 'keeps native additive string-ID requests idempotent without replacing corporate or eligibility records' do
    original = team.team_members.sole.id
    grant_ids = JrcContactCenter::AccessGrant.where(account: account).pluck(:id)
    post endpoint, headers: headers, params: { user_ids: [recipient.id.to_s] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(team.team_members.reload.pluck(:id)).to eq([original])
    expect(JrcContactCenter::AccessGrant.where(account: account).pluck(:id)).to match_array(grant_ids)
    expect(source.reload).to be_active
  end

  it 'rejects foreign user strings before changing the roster or its inherited authority' do
    foreign = create(:user, account: create(:account))
    original = team.team_members.sole.id
    patch endpoint, headers: headers, params: { user_ids: [recipient.id.to_s, foreign.id.to_s] }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(team.team_members.reload.pluck(:id)).to eq([original])
    expect(JrcContactCenter::ModulePolicy.new(context, :contact_center)).to be_operate
    expect(coverage).to be_group
  end

  it 'preserves native team replacement with canonical string IDs when Call Center is disabled' do
    account.disable_features!('jrc_contact_center')
    original = team.team_members.sole.id
    patch endpoint, headers: headers, params: { user_ids: [recipient.id.to_s] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(team.team_members.reload.pluck(:id)).to eq([original])
    expect(coverage).to be_group
  end

  it 'keeps explicit string-ID removal effective without deleting dormant source or individual eligibility' do
    delete endpoint, headers: headers, params: { user_ids: [recipient.id.to_s] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(team.team_members.reload).to be_empty
    expect(source.reload).to be_active
    expect(JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member)).to be_eligible
    expect(JrcContactCenter::ModulePolicy.new(context, :contact_center)).not_to be_operate
    expect(coverage).not_to be_group
  end
end
