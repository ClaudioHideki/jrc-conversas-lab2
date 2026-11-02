# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk native linked resources', :approval_core, type: :request do
  include_context 'JRC Service Desk domain'
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/case_workspaces" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:problem) do
    JrcServiceDesk::CreateIncidentService.new(user_context: sd_context).call(unit_id: sd_unit.id,
                                                                             attributes: { resource_kind: 'problem', title: 'Synthetic linked problem', severity: 'normal' }, idempotency_key: SecureRandom.uuid)
  end
  let(:project) do
    JrcProjects::Projects::Create.call(account: sd_account, actor: sd_user, attributes: { name: 'Synthetic problem action plan' },
                                       idempotency_key: SecureRandom.uuid)
  end
  let(:portal) { create(:portal, account: sd_account) }
  let(:scope) do
    value = approval_scope(account: sd_account)
    value[:unit].update!(settings: value[:unit].settings.merge('service_desk_unit_id' => sd_unit.id.to_s))
    JrcCrm::UserBusinessUnit.create!(account: sd_account, user: sd_user, company: value[:company], business_unit: value[:unit],
                                     scope: 'BUSINESS_UNIT', structure_managed: true, active: true)
    value
  end
  let(:approver) do
    member = approval_actor(scope, permissions: JrcApprovals::Authorization::PERMISSIONS + JrcServiceDesk::Capabilities::PERMISSIONS)
    create(:jrc_sd_membership, unit: sd_unit, account_user: member)
    member
  end

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_projects')
    sd_account_user.update!(jrc_projects_enabled: true)
  end

  def command(action, attributes, key: SecureRandom.uuid)
    post "#{base}/#{problem.id}/commands", headers: headers.merge('Idempotency-Key' => key), as: :json,
                                           params: { action: action, attributes: attributes, expected_lock_version: problem.reload.lock_version }
  end
  it 'offers an authorized corporate unit without granting company-wide approval scope' do
    scope
    get "#{base}/#{problem.id}/resource_options", headers: headers
    expect(response).to have_http_status(:ok), response.body
    company = response.parsed_body.fetch('approval_companies').find { |row| row['id'] == scope[:company].id.to_s }
    expect(company).to include('company_scope_allowed' => false)
    expect(company.fetch('units').map { |row| row['id'] }).to eq([scope[:unit].id.to_s])
    expect do
      JrcApprovals::Authorization.new(account: sd_account, user: sd_user).authorize!('request_create', company_id: scope[:company].id,
                                                                                                       unit_id: nil)
    end.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'creates an official project task once with native dates, assignee, board and audit; soft unlink keeps the task' do
    attrs = { project_id: project.id,
              task: { title: 'Synthetic corrective action', assignee_id: sd_user.id, starts_on: '2026-10-24', due_on: '2026-10-30' } }
    command('create_project_task', attrs, key: 'native-task-once')
    expect(response).to have_http_status(:ok), response.body
    task = project.tasks.find_by!(title: 'Synthetic corrective action')
    expect(task).to have_attributes(assignee_id: sd_user.id, starts_on: Date.new(2026, 10, 24), due_on: Date.new(2026, 10, 30), status: 'backlog')
    expect(JrcProjects::AuditEvent.where(auditable_type: task.class.name, auditable_id: task.id, action: 'projects.task.created').count).to eq(1)
    command('create_project_task', attrs, key: 'native-task-once')
    expect(response).to have_http_status(:ok)
    expect(project.tasks.count).to eq(1)
    get "#{base}/#{problem.id}/resources", headers: headers, params: { kind: 'tasks', linked: 'true' }
    expect(response.parsed_body.fetch('items').map { |row| row['id'] }).to eq([task.id.to_s])
    command('unlink_resource', { kind: 'tasks', id: task.id })
    expect(response).to have_http_status(:ok), response.body
    expect(task.reload.status).to eq('backlog')
    expect(problem.resource_links.where(active: true)).to be_empty
  end

  it 'preserves the native WIP limit and rolls back the link and case journal' do
    project.board_columns.find_by!(status_key: 'backlog').update!(wip_limit: 1)
    JrcProjects::Tasks::Create.call(account_user: sd_account_user, project: project, attributes: { title: 'Existing work' })
    count = problem.incident_entries.count
    command('create_project_task', { project_id: project.id, task: { title: 'Exceeds native WIP' } })
    expect(response).to have_http_status(:unprocessable_entity), response.body
    expect(project.tasks.count).to eq(1)
    expect(problem.incident_entries.count).to eq(count)
  end

  it 'does not expose projects or create tasks after native project permission is revoked' do
    project
    problem
    sd_account.disable_features!('jrc_projects')
    command('create_project_task', { project_id: project.id, task: { title: 'Denied task' } })
    expect(response).to have_http_status(:not_found)
    expect(project.tasks).to be_empty
    get "#{base}/#{problem.id}/resource_options", headers: headers
    expect(response.parsed_body.fetch('projects')).to be_empty
  end

  it 'creates a native knowledge draft without publishing and keeps it after unlink' do
    command('create_article', { portal_id: portal.id, title: 'Synthetic known error', content: 'Synthetic workaround' })
    expect(response).to have_http_status(:ok), response.body
    article = portal.articles.find_by!(title: 'Synthetic known error')
    expect(article).to be_draft
    expect(article.author_id).to eq(sd_user.id)
    command('unlink_resource', { kind: 'articles', id: article.id })
    expect(response).to have_http_status(:ok)
    expect(article.reload).to be_draft
  end

  it 'rejects a portal from another Account without article or link side effects' do
    foreign = create(:portal)
    command('create_article', { portal_id: foreign.id, title: 'Forbidden', content: 'Never persisted' })
    expect(response).to have_http_status(:not_found)
    expect(Article.where(title: 'Forbidden')).to be_empty
    expect(problem.resource_links).to be_empty
  end

  it 'requires an explicitly published approval policy and creates no implicit approvers or requests' do
    scope
    count = JrcApprovals::Policy.count
    command('request_approval', { issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id })
    expect(response).to have_http_status(:unprocessable_entity), response.body
    expect(JrcApprovals::Policy.count).to eq(count)
    expect(JrcApprovals::Request.where(account: sd_account)).to be_empty
    expect(problem.reload.approval_issuer_company_id).to be_nil
  end

  it 'uses the native policy/version, separate authorized approver and stale context protection' do
    scope
    manager = JrcApprovals::Policies.new(account: sd_account, user: sd_user)
    policy = manager.create!(code: 'SYNTHETIC_PROBLEM', name: 'Synthetic change review', module_key: 'service_desk', event_key: 'problem_change',
                             issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id, definition: approval_definition([approver]))
    manager.validate!(policy_id: policy.id, expected_version: policy.lock_version)
    manager.publish!(policy_id: policy.id, expected_version: policy.reload.lock_version)
    command('request_approval', { issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id })
    expect(response).to have_http_status(:ok), response.body
    request = JrcApprovals::Request.find_by!(resource_type: problem.class.name, resource_id: problem.id)
    expect(request.policy_version_id).to eq(policy.reload.current_version_id)
    expect(request.state).to eq('pending')
    command('update', { title: 'Changed evidence after approval request' })
    expect(response).to have_http_status(:ok)
    expect { approval_vote(scope, approver, request) }.to raise_error(JrcApprovals::Error, 'CONTEXT_STALE')
    expect(problem.reload.status).to eq('open')
  end

  it 'preserves native authorized task deletion after unlink without cascading into the problem or its journal' do
    command('create_project_task', { project_id: project.id, task: { title: 'Synthetic task to delete explicitly' } })
    expect(response).to have_http_status(:ok), response.body
    task = project.tasks.find_by!(title: 'Synthetic task to delete explicitly')
    command('unlink_resource', { kind: 'tasks', id: task.id })
    expect(response).to have_http_status(:ok)
    entries = problem.incident_entries.count
    delete "/api/v1/accounts/#{sd_account.id}/projects/projects/#{project.id}/tasks/#{task.id}", headers: headers
    expect(response).to have_http_status(:no_content), response.body
    expect(problem.reload.status).to eq('open')
    expect(problem.incident_entries.count).to eq(entries)
  end

  it 'preserves case history when an article is explicitly removed by its native owner' do
    command('create_article', { portal_id: portal.id, title: 'Synthetic draft with native lifecycle', content: 'Synthetic draft' })
    expect(response).to have_http_status(:ok)
    article = portal.articles.find_by!(title: 'Synthetic draft with native lifecycle')
    count = problem.incident_entries.count
    article.destroy!
    expect(problem.reload.status).to eq('open')
    expect(problem.incident_entries.count).to eq(count)
    expect(problem.resource_links.where(article_id: article.id)).to be_empty
  end
end
