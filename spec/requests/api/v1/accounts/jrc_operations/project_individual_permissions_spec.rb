# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Individual Projects permissions without global role changes', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:url) { "/api/v1/accounts/#{account.id}/projects/projects" }

  before do
    account.enable_features!('jrc_projects')
    member.update!(jrc_projects_enabled: true)
  end

  it 'allows module viewing but blocks project creation until explicitly granted' do
    post url, params: { project: { name: 'Not authorized' } }, headers: agent.create_new_auth_token.merge('Idempotency-Key' => SecureRandom.uuid), as: :json
    expect(response).to have_http_status(:forbidden)
    expect(JrcProjects::Project.where(account: account)).to be_empty
    member.update!(jrc_projects_permissions: { 'projects.project.create' => true })
    post url, params: { project: { name: 'Authorized project' } }, headers: agent.create_new_auth_token.merge('Idempotency-Key' => SecureRandom.uuid), as: :json
    expect(response).to have_http_status(:created), response.body
    expect(member.reload).to have_attributes(role: 'agent', custom_role_id: nil)
  end

  it 'keeps native administrators and scoped project managers separate from individual creation permission' do
    admin_member = account.account_users.find_by!(user: admin)
    project = JrcProjects::Project.create!(account: account, owner: admin, name: 'Managed project', key: 'SYNTHETIC',
      idempotency_key: SecureRandom.uuid, request_fingerprint: 'a' * 64)
    project.project_members.create!(account: account, user: agent, role: 'manager')
    expect(JrcProjects::Authorization.allowed?(account_user: admin_member, capability: 'projects.project.create')).to be(true)
    expect(JrcProjects::Authorization.allowed?(account_user: member, capability: 'projects.project.update', project: project)).to be(true)
    expect(JrcProjects::Authorization.allowed?(account_user: member, capability: 'projects.project.create')).to be(false)
    member.update!(jrc_projects_permissions: { 'projects.time_entry.view' => false })
    projection = JrcProjects::ReadProjection.new(account_user: member, projects: [project])
    expect(projection.capabilities(project)).not_to include('projects.time_entry.view')
    get "/api/v1/accounts/#{account.id}/projects/projects/#{project.id}/time_entries", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    get "#{url}/#{project.id}", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'overview')).not_to have_key('worked_minutes')
    get "#{url}/#{project.id}/reports", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data')).not_to have_key('time_minutes')
    member.update!(jrc_projects_permissions: { 'projects.report.view' => false })
    get "/api/v1/accounts/#{account.id}/projects/portfolio", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    member.update!(jrc_projects_permissions: { 'projects.planning.view' => false })
    get "#{url}/#{project.id}/phases", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
  end

  it 'cannot use an individual allow to bypass a restrictive CustomRole' do
    role = create(:custom_role, account: account, permissions: ['jrc_projects_project_view'])
    member.update!(custom_role: role, jrc_projects_permissions: { 'projects.project.create' => true })
    expect(JrcProjects::Authorization.allowed?(account_user: member, capability: 'projects.project.create')).to be(false)
  end
end
