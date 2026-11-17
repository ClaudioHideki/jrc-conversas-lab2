require 'rails_helper'

RSpec.describe 'Call Center effective authorities in the native authenticated profile', type: :request do
  let(:account) { create(:account) }
  let(:operator) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: operator) }
  let!(:headers) { operator.create_new_auth_token }
  let(:role) { create(:custom_role, account: account, permissions: %w[conversation_manage jrc_contact_center_view]) }
  let(:team) { create(:team, account: account) }
  let(:grant) { JrcContactCenter::AccessGrant.find_by!(account_user: member) }
  let(:permissions) { response.parsed_body.fetch('accounts').find { |entry| entry.fetch('id') == account.id }.fetch('permissions') }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles')
    member.update!(custom_role: role)
    team.add_members([operator.id])
    JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: ['jrc_contact_center_supervise'])
  end

  it 'exports inherited effective authorities while preserving other modules and the custom role marker' do
    get '/api/v1/profile', headers: headers
    expect(response).to have_http_status(:ok)
    expect(permissions).to include('conversation_manage', 'custom_role', 'jrc_contact_center_supervise', 'jrc_contact_center_reports')
    expect(permissions).not_to include('jrc_contact_center_configure', 'jrc_contact_center_recordings_view')
    expect(role.reload.permissions).to eq(%w[conversation_manage jrc_contact_center_view])
  end

  it 'does not export an individually denied report even when supervision is inherited' do
    grant.update!(denied: ['jrc_contact_center_reports'])
    get '/api/v1/profile', headers: headers
    expect(response).to have_http_status(:ok)
    expect(permissions).to include('conversation_manage', 'jrc_contact_center_supervise')
    expect(permissions).not_to include('jrc_contact_center_reports')
  end

  it 'removes all CC authorities when view is denied without revoking unrelated permissions' do
    grant.update!(denied: ['jrc_contact_center_view'])
    get '/api/v1/profile', headers: headers
    expect(response).to have_http_status(:ok)
    expect(permissions & JrcContactCenter::ModulePolicy::PERMISSIONS).to eq([])
    expect(permissions).to include('conversation_manage', 'custom_role')
  end

  it 'does not expose native administrator fallback when explicit eligibility is revoked' do
    member.update!(role: :administrator, custom_role: nil)
    grant.update!(eligible: false)
    get '/api/v1/profile', headers: headers
    expect(response).to have_http_status(:ok)
    expect(permissions).to include('administrator')
    expect(permissions & JrcContactCenter::ModulePolicy::PERMISSIONS).to eq([])
  end

  it 'does not turn a restricted administrator into a CC configuration administrator' do
    member.update!(role: :administrator)
    get '/api/v1/profile', headers: headers
    expect(response).to have_http_status(:ok)
    expect(permissions).to include('jrc_contact_center_view', 'jrc_contact_center_supervise')
    expect(permissions).not_to include('jrc_contact_center_configure', 'jrc_contact_center_administer')
  end

  it 'preserves the authorized native fallback but does not grant the new critical capabilities' do
    member.update!(role: :administrator, custom_role: nil)
    get '/api/v1/profile', headers: headers
    expect(response).to have_http_status(:ok)
    expect(permissions).to include('administrator', 'jrc_contact_center_view', 'jrc_contact_center_configure')
    expect(permissions).not_to include('jrc_contact_center_administer', 'jrc_contact_center_publish', 'jrc_contact_center_approve')
  end

  it 'does not export raw CC profile entries when the account feature is disabled' do
    account.disable_features!('jrc_contact_center')
    get '/api/v1/profile', headers: headers
    expect(response).to have_http_status(:ok)
    expect(permissions & JrcContactCenter::ModulePolicy::PERMISSIONS).to eq([])
    expect(permissions).to include('conversation_manage', 'custom_role')
  end

  it 'does not reuse authorities from the same user team in another account' do
    foreign = create(:account)
    create(:account_user, account: foreign, user: operator)
    foreign_team = create(:team, account: foreign)
    foreign_team.add_members([operator.id])
    JrcContactCenter::AccessGrant.create!(account: foreign, team: foreign_team, allowed: ['jrc_contact_center_administer'])
    get '/api/v1/profile', headers: headers
    expect(response).to have_http_status(:ok)
    expect(permissions).to include('jrc_contact_center_supervise')
    expect(permissions).not_to include('jrc_contact_center_administer')
  end

  it 'refreshes team and eligibility changes on a new authenticated request instead of caching old grants' do
    get '/api/v1/profile', headers: headers
    expect(permissions).to include('jrc_contact_center_supervise')
    team.team_members.find_by!(user: operator).destroy!
    grant.update!(eligible: false)
    get '/api/v1/profile', headers: headers
    fresh = response.parsed_body.fetch('accounts').find { |entry| entry.fetch('id') == account.id }.fetch('permissions')
    expect(fresh & JrcContactCenter::ModulePolicy::PERMISSIONS).to eq([])
    expect(fresh).to include('conversation_manage', 'custom_role')
  end
end
