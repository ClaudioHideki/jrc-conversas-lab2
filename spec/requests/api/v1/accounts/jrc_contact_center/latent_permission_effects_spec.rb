require 'rails_helper'

RSpec.describe 'Call Center latent permission dependency guards', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let!(:headers) { actor.create_new_auth_token }
  let(:actor_link) { account.account_users.find_by!(user: actor) }
  let(:actor_role) { create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_administer]) }
  let(:recipient) { create(:user, :contact_center_eligible, account: account) }
  let(:member) { account.account_users.find_by!(user: recipient) }
  let(:grant) { JrcContactCenter::AccessGrant.find_by!(account_user: member) }
  let(:base) { "/api/v1/accounts/#{account.id}" }
  let(:service) { JrcContactCenter::AccessAuthorization.new(context: { account: account, account_user: actor_link, user: actor }) }
  let(:unviewable) { create(:custom_role, account: account, permissions: ['contact_manage']) }
  let(:team) { create(:team, account: account) }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    actor_link.update!(custom_role: actor_role)
    member.update!(custom_role: unviewable)
  end

  it 'does not store a critical individual grant even when it is not effective yet' do
    attributes = { authorization: { allowed: ['jrc_contact_center_publish'] }, expected_revision: service.revision(member, grant) }
    patch "#{base}/jrc_contact_center/access_authorizations/users/#{member.id}", headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(grant.reload.allowed).to eq([])
  end

  it 'does not activate an existing individual critical grant merely by assigning a view profile' do
    grant.update!(allowed: ['jrc_contact_center_publish'])
    view_role = create(:custom_role, account: account, permissions: ['jrc_contact_center_view'])
    attributes = { agent: { name: 'Forbidden' }, custom_role_id: view_role.id }
    patch "#{base}/agents/#{recipient.id}", headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(member.reload.custom_role_id).to eq(unviewable.id)
    expect(recipient.reload.name).not_to eq('Forbidden')
  end

  it 'does not activate a critical profile capability by adding only the view dependency' do
    critical = create(:custom_role, account: account, permissions: ['jrc_contact_center_publish'])
    member.update!(custom_role: critical)
    attributes = { custom_role: { permissions: %w[jrc_contact_center_publish jrc_contact_center_view] } }
    patch "#{base}/custom_roles/#{critical.id}", headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(critical.reload.permissions).to eq(['jrc_contact_center_publish'])
  end

  it 'does not activate a critical team grant by adding only the view dependency' do
    team.add_members([recipient.id])
    team_grant = JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: ['jrc_contact_center_publish'])
    attributes = { authorization: { allowed: %w[jrc_contact_center_publish jrc_contact_center_view] },
                   expected_revision: service.revision(team, team_grant) }
    patch "#{base}/jrc_contact_center/access_authorizations/teams/#{team.id}", headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(team_grant.reload.allowed).to eq(['jrc_contact_center_publish'])
  end

  it 'does not activate a latent profile capability through a native team membership' do
    critical = create(:custom_role, account: account, permissions: ['jrc_contact_center_publish'])
    member.update!(custom_role: critical)
    JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: ['jrc_contact_center_view'])
    post "#{base}/teams/#{team.id}/team_members", headers: headers, params: { user_ids: [recipient.id] }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(team.team_members.where(user: recipient)).to be_empty
  end

  it 'allows the same transition when the actor actually holds its full effective result' do
    actor_role.update!(permissions: actor_role.permissions + ['jrc_contact_center_publish'])
    grant.update!(allowed: ['jrc_contact_center_publish'])
    view_role = create(:custom_role, account: account, permissions: ['jrc_contact_center_view'])
    attributes = { agent: { name: 'SYNTHETIC permitted' }, custom_role_id: view_role.id }
    patch "#{base}/agents/#{recipient.id}", headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:ok)
    policy = JrcContactCenter::ModulePolicy.new({ account: account, account_user: member.reload, user: recipient }, :contact_center)
    expect(policy.publish?).to be(true)
  end
end
