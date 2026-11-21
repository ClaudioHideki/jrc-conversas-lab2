require 'rails_helper'

RSpec.describe 'Call Center Nico review permissions in authenticated native APIs', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let!(:headers) { actor.create_new_auth_token }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:grant) { JrcContactCenter::AccessGrant.find_by!(account_user: member) }
  let(:review) { 'jrc_contact_center_quality_review' }
  let(:recording) { %w[jrc_contact_center_view jrc_contact_center_recordings_view jrc_contact_center_recordings_listen] }
  let(:role) { create(:custom_role, account: account, permissions: recording) }
  let(:permissions) { response.parsed_body.fetch('accounts').find { |item| item.fetch('id') == account.id }.fetch('permissions') }

  before { account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs') }

  it 'does not export a new review right merely because the authenticated user is an administrator' do
    grant.update!(allowed: recording)
    get '/api/v1/profile', headers: headers
    expect(response).to have_http_status(:ok)
    expect(permissions).to include('administrator', 'jrc_contact_center_recordings_listen')
    expect(permissions).not_to include(review)
  end

  it 'exports an explicit profile grant and removes it after a fresh recording-access denial' do
    role.update!(permissions: recording + [review])
    member.update!(custom_role: role)
    get '/api/v1/profile', headers: headers
    expect(response).to have_http_status(:ok)
    expect(permissions).to include(review)
    grant.update!(denied: ['jrc_contact_center_recordings_listen'])
    get '/api/v1/profile', headers: headers
    expect(response).to have_http_status(:ok)
    fresh = response.parsed_body.fetch('accounts').find { |item| item.fetch('id') == account.id }.fetch('permissions')
    expect(fresh).not_to include(review)
    expect(fresh).not_to include('jrc_contact_center_recordings_listen')
    expect(role.reload.permissions).to include(review)
  end

  it 'does not let a native administrator add the new authority through the existing profile API' do
    member.update!(custom_role: nil)
    grant.update!(allowed: recording)
    role
    previous = Enterprise::AuditLog.where(associated: account).count
    attributes = { custom_role: { permissions: recording + [review] } }
    patch "/api/v1/accounts/#{account.id}/custom_roles/#{role.id}", headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(role.reload.permissions).to eq(recording)
    expect(Enterprise::AuditLog.where(associated: account).count).to eq(previous)
    expect(grant.reload.allowed).not_to include(review)
  end

  it 'does not allow removal of a restrictive profile to manufacture the new review permission' do
    member.update!(custom_role: role)
    patch "/api/v1/accounts/#{account.id}/agents/#{actor.id}", headers: headers, params: { custom_role_id: nil }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(member.reload.custom_role_id).to eq(role.id)
    get '/api/v1/profile', headers: headers
    expect(permissions).not_to include(review)
  end

  it 'keeps foreign native profiles inaccessible through the ordinary update route' do
    foreign = create(:custom_role, account: create(:account), permissions: recording + [review])
    attributes = { custom_role: { permissions: [] } }
    patch "/api/v1/accounts/#{account.id}/custom_roles/#{foreign.id}", headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.permissions).to eq(recording + [review])
    get '/api/v1/profile', headers: headers
    expect(permissions).not_to include(review)
  end

  it 'allows an explicitly authorized synthetic actor to update a native profile with an actor audit' do
    grant.update!(allowed: recording + [review])
    attributes = { custom_role: { permissions: recording + [review] } }
    patch "/api/v1/accounts/#{account.id}/custom_roles/#{role.id}", headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:ok)
    expect(role.reload.permissions).to include(review)
    audit = Enterprise::AuditLog.where(comment: 'JRC Call Center native capabilities', associated: account).last
    expect(audit.user_id).to eq(actor.id)
    expect(audit.request_uuid).to be_present
  end

  it 'persists the new right through native team authorization without changing team membership or activating users' do
    grant.update!(allowed: recording + [review, 'jrc_contact_center_administer'])
    team = create(:team, account: account)
    base = "/api/v1/accounts/#{account.id}/jrc_contact_center/access_authorizations/teams/#{team.id}"
    get base, headers: headers
    expect(response).to have_http_status(:ok)
    expected = response.parsed_body.fetch('item').fetch('revision')
    attributes = { authorization: { allowed: [review] }, expected_revision: expected }
    patch base, headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:ok)
    saved = JrcContactCenter::AccessGrant.find_by!(account: account, team: team)
    expect(saved.allowed).to eq([review])
    expect(saved.eligible).to be(false)
    expect(saved.denied).to eq([])
    expect(team.team_members).to be_empty
  end

  it 'denies a recording-rights edit that would reactivate a latent review grant above actor authority' do
    grant.update!(allowed: recording)
    role.update!(permissions: ['jrc_contact_center_view', review])
    recipient = create(:user, :contact_center_eligible, account: account)
    account.account_users.find_by!(user: recipient).update!(custom_role: role)
    before = role.attributes
    attributes = { custom_role: { permissions: recording + [review] } }
    patch "/api/v1/accounts/#{account.id}/custom_roles/#{role.id}", headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(role.reload.attributes).to eq(before)
  end

  it 'treats removal of an explicit review denial as a grant, preserving the denial when the actor lacks it' do
    grant.update!(allowed: recording + ['jrc_contact_center_administer'])
    role.update!(permissions: recording + [review])
    recipient = create(:user, :contact_center_eligible, account: account)
    target = account.account_users.find_by!(user: recipient)
    target.update!(custom_role: role)
    existing = JrcContactCenter::AccessGrant.find_by!(account_user: target)
    existing.update!(denied: [review])
    base = "/api/v1/accounts/#{account.id}/jrc_contact_center/access_authorizations/users/#{target.id}"
    get base, headers: headers
    expect(response).to have_http_status(:ok)
    expected = response.parsed_body.fetch('item').fetch('revision')
    attributes = { authorization: { denied: [] }, expected_revision: expected }
    patch base, headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(existing.reload.denied).to eq([review])
    expect(role.reload.permissions).to eq(recording + [review])
  end
end
