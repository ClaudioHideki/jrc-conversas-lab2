require 'rails_helper'

RSpec.describe 'Scoped native analyst responsibility origins', type: :request do
  include_context 'JRC Service Desk domain'
  let(:headers) { sd_user.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{sd_account.id}/relationship/team/#{sd_user.id}/native_responsibilities" }
  let(:project) do
    JrcProjects::Projects::Create.call(account: sd_account, actor: sd_user, attributes: { name: 'Real native source', contact_id: sd_contact.id },
                                       idempotency_key: SecureRandom.uuid)
  end
  let(:assignment) { JrcRelationship::Assignment.create!(account: sd_account, owner: sd_user, contact: sd_contact) }
  let(:plan) do
    JrcRelationship::SuccessPlan.create!(account: sd_account, assignment: assignment, owner: sd_user, project: project,
                                         title: 'Synthetic current CS project link')
  end

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm', 'jrc_projects')
  end

  it 'paginates actual pending task ownership and opens the precise native task without changing owners or memberships' do
    plan
    tasks = Array.new(11) do |index|
      JrcProjects::Tasks::Create.call(account_user: sd_account_user, project: project,
                                      attributes: { title: "Pending native task #{index}", assignee_id: sd_user.id },
                                      correlation_id: SecureRandom.uuid)
    end
    JrcProjects::Task.create!(account: sd_account, project: project, created_by: sd_user, assignee: sd_user,
                              title: 'Historical completed task', status: 'completed')
    before = project.project_members.order(:id).map(&:attributes)
    get url, headers: headers, params: { kind: 'project_tasks' }
    expect(response).to have_http_status(:ok), response.body
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.parsed_body.fetch('meta')).to include('total' => 11, 'per_page' => 10, 'page' => 1)
    get url, headers: headers, params: { kind: 'project_tasks', page: 2 }
    route = { 'name' => 'jrc_projects_detail', 'params' => { 'accountId' => sd_account.id, 'projectId' => project.id },
              'query' => { 'taskId' => tasks.last.id } }
    expected = { 'id' => tasks.last.id, 'title' => tasks.last.title, 'source_route' => route }
    expect(response.parsed_body.fetch('payload')).to contain_exactly(include(expected))
    expect(response.body).not_to include('Historical completed task', 'custom_fields', 'attachments')
    expect([tasks.map { |row| row.reload.assignee_id }.uniq, project.reload.owner_id, project.project_members.order(:id).map(&:attributes)])
      .to eq([[sd_user.id], sd_user.id, before])
  end

  it 'lists real pending unit membership tickets while omitting descriptions and completed history' do
    ticket = sd_ticket(assignee_membership: sd_membership, title: 'Current native ticket', description: 'Private body must not be projected')
    JrcRelationship::Action.create!(account: sd_account, assignment: assignment, owner: sd_user, kind: 'manual',
                                    reason: 'Synthetic linked ticket', source_key: SecureRandom.uuid,
                                    metadata: { '_source_ids' => { 'tickets' => [ticket.id] } })
    closed = create(:jrc_sd_status, unit: sd_unit, phase: 'closed', initial: false)
    history = sd_ticket(assignee_membership: sd_membership, title: 'Closed historical case')
    history.update!(status: closed)
    before = ticket.attributes.deep_dup
    get url, headers: headers, params: { kind: 'service_tickets', unit_id: sd_foreign_unit.id }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('meta')).to include('total' => 1)
    route = { 'name' => 'jrc_service_desk_detail', 'params' => { 'accountId' => sd_account.id, 'ticketId' => ticket.id } }
    expect(response.parsed_body.fetch('payload')).to contain_exactly(include('id' => ticket.id, 'status' => 'open', 'source_route' => route))
    expect(response.body).not_to include('Private body must not be projected', 'Closed historical case', 'assignee_membership_id')
    expect(ticket.reload.attributes).to eq(before)
  end

  it 'lists owned active projects through native project visibility and excludes final projects' do
    plan
    get url, headers: headers, params: { kind: 'projects' }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('payload')).to contain_exactly(include('id' => project.id))
    project.update!(status: 'completed')
    get url, headers: headers, params: { kind: 'projects' }
    expect(response.parsed_body.fetch('meta')).to include('total' => 0)
  end

  it 'respects native operator and unit grants and never exposes a partial count when the analyst also owns hidden tickets' do
    analyst = create(:user, account: sd_account, role: :agent)
    member = sd_account.account_users.find_by!(user: analyst)
    visible_membership = create(:jrc_sd_membership, unit: sd_unit, account_user: member)
    visible = sd_ticket(assignee_membership: visible_membership)
    evidence = JrcRelationship::Action.create!(account: sd_account, assignment: assignment, owner: sd_user, kind: 'manual',
                                               reason: 'Synthetic linked unit work', source_key: SecureRandom.uuid,
                                               metadata: { '_source_ids' => { 'tickets' => [visible.id] } })
    permissions = %w[contact_manage jrc_relationship_view jrc_relationship_team jrc_service_desk_module_view
                     jrc_service_desk_tickets_view jrc_service_desk_tickets_view_all jrc_service_desk_customers_view]
    role = create(:custom_role, account: sd_account, permissions: permissions)
    sd_account_user.update!(role: :agent, custom_role: role)
    selected_url = "/api/v1/accounts/#{sd_account.id}/relationship/team/#{analyst.id}/native_responsibilities"
    get selected_url, headers: headers, params: { kind: 'service_tickets' }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([visible.id])
    other_operator = create(:jrc_sd_operator_company, account: sd_account)
    other_unit = create(:jrc_sd_unit, operator_company: other_operator)
    hidden_member = create(:jrc_sd_membership, unit: other_unit, account_user: member)
    status = create(:jrc_sd_status, unit: other_unit)
    priority = create(:jrc_sd_priority, unit: other_unit)
    hidden = sd_ticket(unit: other_unit, status: status, priority: priority, created_by_membership: hidden_member,
                       assignee_membership: hidden_member, title: 'Hidden other operator workload')
    evidence.update!(metadata: { '_source_ids' => { 'tickets' => [visible.id, hidden.id] } })
    get selected_url, headers: headers, params: { kind: 'service_tickets', unit_id: sd_unit.id, operating_company_id: sd_operator.id }
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include('total', 'payload', 'Hidden other operator workload')
  end

  it 'denies private project ownership before totals and does not grant source visibility through selected IDs' do
    analyst = create(:user, account: sd_account, role: :administrator)
    hidden = JrcProjects::Projects::Create.call(account: sd_account, actor: analyst,
                                                attributes: { name: 'Hidden native project', visibility: 'private' },
                                                idempotency_key: SecureRandom.uuid)
    JrcRelationship::SuccessPlan.create!(account: sd_account, assignment: assignment, owner: sd_user, project: hidden,
                                         title: 'Synthetic private native CS link')
    permissions = %w[contact_manage jrc_relationship_view jrc_relationship_team jrc_projects_project_view jrc_projects_task_view]
    role = create(:custom_role, account: sd_account, permissions: permissions)
    sd_account_user.update!(role: :agent, custom_role: role, jrc_projects_enabled: true)
    selected_url = "/api/v1/accounts/#{sd_account.id}/relationship/team/#{analyst.id}/native_responsibilities"
    get selected_url, headers: headers, params: { kind: 'projects', project_id: hidden.id }
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include('Hidden native project', 'total', 'payload')
  end

  it 'rejects foreign accounts, foreign analysts, missing native capabilities and non-team readers without workload disclosure' do
    foreign_user = create(:user, account: sd_foreign_account, role: :administrator)
    get "/api/v1/accounts/#{sd_account.id}/relationship/team/#{foreign_user.id}/native_responsibilities", headers: headers
    expect(response).to have_http_status(:not_found)
    get "/api/v1/accounts/#{sd_foreign_account.id}/relationship/team/#{sd_user.id}/native_responsibilities", headers: headers
    expect(response).to have_http_status(:forbidden)
    role = create(:custom_role, account: sd_account, permissions: %w[contact_manage jrc_relationship_view])
    sd_account_user.update!(role: :agent, custom_role: role)
    get url, headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include('total', 'payload')
  end

  it 'does not turn native project capability revocation into an empty or disclosed responsibility list' do
    plan
    role = create(:custom_role, account: sd_account,
                                permissions: %w[contact_manage jrc_relationship_view jrc_relationship_team jrc_projects_project_view])
    sd_account_user.update!(role: :agent, custom_role: role, jrc_projects_enabled: false)
    get url, headers: headers, params: { kind: 'projects', user_id: sd_user.id }
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include('total', 'payload', project.name)
  end

  it 'rechecks native capabilities before disclosing a list if the grant is revoked during the query' do
    plan
    role = create(:custom_role, account: sd_account,
                                permissions: %w[contact_manage jrc_relationship_view jrc_relationship_team jrc_projects_project_view])
    checks = 0
    allow(JrcOperations::Access).to receive(:projects).and_wrap_original do |original, *args|
      scope = original.call(*args)
      checks += 1
      sd_account_user.update!(role: :agent, custom_role: role, jrc_projects_enabled: false) if checks == 1
      scope
    end
    get url, headers: headers, params: { kind: 'projects' }
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include('total', 'payload', project.name)
  end

  it 'validates category and pagination and handles out-of-range pages without an overflowing SQL offset' do
    get url, headers: headers, params: { kind: 'credentials' }
    expect(response).to have_http_status(:unprocessable_entity)
    get url, headers: headers, params: { page: 0 }
    expect(response).to have_http_status(:bad_request)
    get url, headers: headers, params: { page: '999999999999999999999999' }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('payload')).to eq([])
  end
end
