require 'rails_helper'

RSpec.describe 'Projects native account authorization', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/projects/projects" }
  let(:settings_url) { "/api/v1/accounts/#{account.id}/projects/settings" }

  describe 'GET operations/status' do
    let(:status_url) { "/api/v1/accounts/#{account.id}/operations/status" }

    it 'loads the navigation context while Projects is disabled without granting access' do
      get status_url, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('data')).to include(
        'ready' => true, 'administrator' => true, 'projects_enabled' => false, 'can_create_project' => false
      )
      expect(account.reload.feature_enabled?('jrc_projects')).to be(false)
    end

    it 'exposes Projects to an administrator only after the account entitlement is enabled' do
      account.enable_features!('jrc_projects')

      get status_url, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('data')).to include(
        'administrator' => true, 'projects_enabled' => true, 'can_create_project' => true
      )
    end

    it 'reflects explicit agent grants and revocation in the navigation context' do
      account.enable_features!('jrc_projects')
      headers = agent.create_new_auth_token

      get status_url, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'projects_enabled')).to be(false)

      member.update!(jrc_projects_enabled: true)
      get status_url, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'projects_enabled')).to be(true)

      member.update!(jrc_projects_enabled: false)
      get status_url, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'projects_enabled')).to be(false)
    end

    it 'does not expose a different account navigation context' do
      other_account = create(:account)

      get "/api/v1/accounts/#{other_account.id}/operations/status", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end

  it 'does not let an account administrator activate its commercial entitlement' do
    patch settings_url, params: { settings: { projects_enabled: true } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(account.reload.feature_enabled?('jrc_projects')).to be(false)
  end

  it 'requires an explicit agent grant and immediately observes revocation' do
    account.enable_features!('jrc_projects')
    get url, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    patch settings_url, params: { settings: { agent_access: [{ account_user_id: member.id, enabled: true }] } },
                        headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    get url, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    member.reload.update!(jrc_projects_enabled: false)
    get url, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    expect(JrcProjects::AuditEvent.where(action: 'projects.access.changed').count).to eq(1)
  end

  it 'rejects grants for another account and agent self-grants' do
    account.enable_features!('jrc_projects')
    foreign = create(:account_user)
    patch settings_url, params: { settings: { agent_access: [{ account_user_id: foreign.id, enabled: true }] } },
                        headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.jrc_projects_enabled?).to be(false)
    patch settings_url, params: { settings: { agent_access: [{ account_user_id: member.id, enabled: true }] } },
                        headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'honors a restrictive CustomRole even with a project grant' do
    account.enable_features!('jrc_projects')
    role = create(:custom_role, account: account, permissions: ['jrc_projects_project_view'])
    member.update!(jrc_projects_enabled: true, custom_role_id: role.id)
    post url, params: { project: { name: 'Unauthorized creation' } },
              headers: agent.create_new_auth_token.merge('Idempotency-Key' => SecureRandom.uuid), as: :json
    expect(response).to have_http_status(:forbidden)
    expect(JrcProjects::Project.where(account: account)).to be_empty
  end

  it 'keeps support tables absent and Broker/Flows flags at their original positions' do
    expect(ActiveRecord::Base.connection.data_source_exists?('jrc_support_tickets')).to be(false)
    flags = YAML.safe_load(File.read(Rails.root.join('config/features.yml'))).select { |f| f['column'] == 'feature_flags_ext_1' }
    expect(flags[8]['name']).to eq('jrc_service_desk')
    expect(flags[9]['name']).to eq('jrc_flows')
    expect(flags[10]['name']).to eq('jrc_broker')
    expect(flags[11]).to include('name' => 'jrc_projects', 'enabled' => false)
  end
end
