require 'rails_helper'

# Real Rails/PostgreSQL request specs. Requires the existing operations migrations
# in a dedicated test database. Structural checks do not execute these examples.
RSpec.describe 'JRC Projects Core checkpoint 3A', type: :request do
  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:colleague) { create(:user, account: account, role: :agent) }
  let(:customer) { create(:contact, account: account) }
  let(:foreign_account) { create(:account) }
  let(:foreign_owner) { create(:user, account: foreign_account, role: :administrator) }
  let(:foreign_contact) { create(:contact, account: foreign_account) }
  let(:headers) { owner.create_new_auth_token }
  let(:collection) { "/api/v1/accounts/#{account.id}/projects/projects" }
  let(:project) do
    JrcProjects::Projects::Create.call(
      account: account, actor: owner, attributes: { name: 'Core project' },
      idempotency_key: SecureRandom.uuid, correlation_id: 'setup-3a'
    )
  end
  let(:endpoint) { "#{collection}/#{project.id}" }

  before do
    [owner, colleague].each { |u| account.account_users.find_by!(user: u).update!(jrc_projects_enabled: true) }
    account.enable_features!('jrc_projects')
  end

  it 'creates an internal project with the actor as initial owner and no source requirement' do
    post collection, params: { project: { name: 'Internal delivery', owner_id: colleague.id } },
                     headers: headers.merge('Idempotency-Key' => SecureRandom.uuid, 'X-Request-Id' => 'core-3a-create'), as: :json
    expect(response).to have_http_status(:created)
    data = response.parsed_body.fetch('data')
    expect(data).to include('contact_id' => nil, 'owner_id' => owner.id, 'priority' => 'medium', 'status' => 'planned', 'progress' => 0)
    record = JrcProjects::Project.find(data.fetch('id'))
    expect(record.operation_links).to be_empty
    expect(record.project_members.pluck(:user_id, :role)).to eq([[owner.id, 'owner']])
    expect(record.boards.count).to eq(1)
    expect(JrcProjects::AuditEvent.find_by!(auditable_id: record.id, action: 'projects.project.created').correlation_id).to eq('core-3a-create')
  end

  it 'creates priority and an optional existing customer without duplicating the contact' do
    customer
    expect do
      post collection, params: { project: { name: 'Customer delivery', contact_id: customer.id, priority: 'urgent' } },
                       headers: headers.merge('Idempotency-Key' => SecureRandom.uuid), as: :json
    end.not_to change(Contact, :count)
    expect(response).to have_http_status(:created)
    record = JrcProjects::Project.find(response.parsed_body.dig('data', 'id'))
    expect(record.settings).to include('priority' => 'urgent')
    expect(record.contact_id).to eq(customer.id)
  end

  it 'filters priority in PostgreSQL with search, status and pagination metadata including legacy medium' do
    project.update!(name: 'Matching delivery', status: 'active')
    JrcProjects::Projects::Create.call(account: account, actor: owner, attributes: { name: 'Matching urgent', priority: 'urgent' },
                                     idempotency_key: SecureRandom.uuid)
    get collection, params: { q: 'Matching', status: 'active', priority: 'medium', per_page: 1 }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data').pluck('id')).to eq([project.id])
    expect(response.parsed_body.dig('meta', 'total')).to eq(1)
    get collection, params: { priority: 'urgent' }, headers: headers
    expect(response.parsed_body.fetch('data').map { |row| row.fetch('priority') }).to eq(['urgent'])
  end

  it 'edits core fields without replacing unrelated settings and audits the correlation id' do
    project.update!(settings: { 'existing_option' => true })
    patch endpoint, params: { project: {
      name: 'Revised delivery', description: 'Reviewed scope', contact_id: customer.id, priority: 'high', visibility: 'private',
      status: 'active', starts_on: '2026-10-01', due_on: '2026-10-31', lock_version: project.lock_version
    } }, headers: headers.merge('X-Request-Id' => 'core-3a-update'), as: :json
    expect(response).to have_http_status(:ok)
    expect(project.reload).to have_attributes(name: 'Revised delivery', description: 'Reviewed scope', contact_id: customer.id,
                                             priority: 'high', visibility: 'private', status: 'active',
                                             starts_on: Date.new(2026, 10, 1), due_on: Date.new(2026, 10, 31))
    expect(project.settings).to include('existing_option' => true, 'priority' => 'high')
    event = JrcProjects::AuditEvent.where(account: account, auditable_id: project.id, action: 'projects.project.updated').last!
    expect(event.correlation_id).to eq('core-3a-update')
    expect(event.before_data).to include('name' => 'Core project', 'priority' => 'medium')
    expect(event.after_data).to include('name' => 'Revised delivery', 'priority' => 'high')
    expect(response.parsed_body.dig('data', 'owner', 'id')).to eq(owner.id)
    expect(response.parsed_body.dig('data', 'contact', 'id')).to eq(customer.id)
    expect(response.parsed_body.dig('data', 'capabilities')).to include('projects.project.transfer')
  end

  it 'can remove the optional customer when the project has no source links' do
    project.update!(contact: customer)
    patch endpoint, params: { project: { contact_id: nil, lock_version: project.lock_version } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(project.reload.contact_id).to be_nil
  end

  it 'transfers ownership as the current owner and reuses team rows without retaining ownership privileges' do
    project.project_members.create!(account: account, user: colleague, role: 'member')
    expect do
      patch endpoint, params: { project: { owner_id: colleague.id, lock_version: project.lock_version } }, headers: headers, as: :json
    end.not_to change(JrcProjects::ProjectMember, :count)
    expect(response).to have_http_status(:ok)
    expect(project.reload.owner_id).to eq(colleague.id)
    expect(project.project_members.find_by!(user: owner).role).to eq('manager')
    expect(project.project_members.find_by!(user: colleague).role).to eq('owner')
    expect(response.parsed_body.dig('data', 'capabilities')).not_to include('projects.project.transfer', 'projects.budget.view')
    patch endpoint, params: { project: { owner_id: owner.id, lock_version: project.lock_version } }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'allows an administrator to transfer ownership to an account user not yet in the team' do
    project
    patch endpoint, params: { project: { owner_id: colleague.id, lock_version: project.lock_version } },
                    headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(project.reload.owner_id).to eq(colleague.id)
    expect(project.project_members.where(account_id: account.id, user_id: colleague.id).pluck(:role)).to eq(['owner'])
  end

  %w[manager owner].each do |role|
    it "does not let the #{role} membership role alone transfer ownership" do
      project.project_members.create!(account: account, user: colleague, role: role)
      patch endpoint, params: { project: { owner_id: colleague.id, lock_version: project.lock_version } },
                      headers: colleague.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(project.reload.owner_id).to eq(owner.id)
    end
  end

  it 'lets managers edit core fields while viewers cannot edit' do
    member = project.project_members.create!(account: account, user: colleague, role: 'manager')
    colleague_headers = colleague.create_new_auth_token
    patch endpoint, params: { project: { name: 'Manager edit', lock_version: project.lock_version } }, headers: colleague_headers, as: :json
    expect(response).to have_http_status(:ok)
    member.update!(role: 'viewer')
    patch endpoint, params: { project: { name: 'Forbidden edit', lock_version: project.reload.lock_version } }, headers: colleague_headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(project.reload.name).to eq('Manager edit')
  end

  it 'does not equate account visibility with permission to edit or create projects' do
    project.update!(visibility: 'account')
    role = create(:custom_role, account: account, permissions: ['jrc_projects_project_view'])
    account.account_users.find_by!(user: colleague).update!(custom_role_id: role.id)
    colleague_headers = colleague.create_new_auth_token
    get endpoint, headers: colleague_headers
    expect(response).to have_http_status(:ok)
    patch endpoint, params: { project: { name: 'Forbidden edit', lock_version: project.lock_version } }, headers: colleague_headers, as: :json
    expect(response).to have_http_status(:forbidden)
    post collection, params: { project: { name: 'Forbidden creation' } },
                     headers: colleague_headers.merge('Idempotency-Key' => SecureRandom.uuid), as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects stale edits and requires lock_version without changing data or audit' do
    project
    expect do
      patch endpoint, params: { project: { name: 'Stale edit', lock_version: -1 } }, headers: headers, as: :json
    end.not_to change(JrcProjects::AuditEvent, :count)
    expect(response).to have_http_status(:conflict)
    expect(project.reload.name).to eq('Core project')
    patch endpoint, params: { project: { name: 'Missing version' } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejects a foreign customer on creation and update' do
    post collection, params: { project: { name: 'Invalid customer', contact_id: foreign_contact.id } },
                     headers: headers.merge('Idempotency-Key' => SecureRandom.uuid), as: :json
    expect(response).to have_http_status(:not_found)
    patch endpoint, params: { project: { contact_id: foreign_contact.id, lock_version: project.lock_version } }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(project.reload.contact_id).to be_nil
  end

  it 'rejects foreign ownership without changing team or recording a successful update' do
    project
    expect do
      patch endpoint, params: { project: { owner_id: foreign_owner.id, lock_version: project.lock_version } }, headers: headers, as: :json
    end.not_to change(JrcProjects::AuditEvent, :count)
    expect(response).to have_http_status(:not_found)
    expect(project.reload.owner_id).to eq(owner.id)
    expect(project.project_members.pluck(:user_id, :role)).to eq([[owner.id, 'owner']])
  end

  it 'does not find or list a foreign project even for the current account administrator' do
    foreign_project = JrcProjects::Project.create!(account: foreign_account, owner: foreign_owner, key: 'FOREIGN', name: 'Foreign project')
    admin_headers = admin.create_new_auth_token
    get "#{collection}/#{foreign_project.id}", headers: admin_headers
    expect(response).to have_http_status(:not_found)
    patch "#{collection}/#{foreign_project.id}", params: { project: { name: 'Invalid edit', lock_version: 0 } }, headers: admin_headers, as: :json
    expect(response).to have_http_status(:not_found)
    get collection, headers: admin_headers
    expect(response.parsed_body.fetch('data').pluck('id')).not_to include(foreign_project.id)
  end

  it 'scopes team member ids by account and project and rejects foreign users' do
    foreign_project = JrcProjects::Project.create!(account: foreign_account, owner: foreign_owner, key: 'FOREIGN', name: 'Foreign project')
    foreign_member = foreign_project.project_members.create!(account: foreign_account, user: foreign_owner, role: 'owner')
    get "#{endpoint}/members/#{foreign_member.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    post "#{endpoint}/members", params: { record: { user_id: foreign_owner.id, role: 'member', allocation_percent: 100 } },
                               headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(project.project_members.pluck(:user_id)).to eq([owner.id])
  end

  %i[ticket conversation crm_deal].each do |source_kind|
    it "preserves the source customer for an existing #{source_kind} link, including removal attempts" do
      project.update!(contact: customer)
      source = case source_kind
               when :ticket
                 unit = create(:jrc_sd_unit, account: account, operator_company: create(:jrc_sd_operator_company, account: account))
                 create(:jrc_sd_ticket, unit: unit, requester: customer)
               when :conversation
                 create(:conversation, account: account, contact: customer)
               when :crm_deal
                 pipeline = create(:jrc_crm_pipeline, account: account)
                 stage = create(:jrc_crm_stage, account: account, pipeline: pipeline)
                 create(:jrc_crm_deal, account: account, owner: owner, contact: customer, pipeline: pipeline, stage: stage)
               end
      link = JrcOperations::Link.create!({ account: account, created_by: owner, project: project }.merge(source_kind => source))
      get endpoint, headers: headers
      expect(response.parsed_body.dig('data', 'contact_locked')).to be(true)
      [nil, create(:contact, account: account).id].each do |candidate|
        patch endpoint, params: { project: { contact_id: candidate, lock_version: project.reload.lock_version } }, headers: headers, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(project.reload.contact_id).to eq(customer.id)
        expect(JrcOperations::Link.exists?(link.id)).to be(true)
      end
      patch endpoint, params: { project: { name: 'Source retained', lock_version: project.lock_version } }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  it 'rolls back an invalid edit together with a requested ownership transfer' do
    project
    patch endpoint, params: { project: { owner_id: colleague.id, starts_on: '2026-10-31', due_on: '2026-10-01',
                                        lock_version: project.lock_version } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(project.reload.owner_id).to eq(owner.id)
    expect(project.project_members.pluck(:user_id, :role)).to eq([[owner.id, 'owner']])
    expect(JrcProjects::AuditEvent.where(auditable_id: project.id, action: 'projects.project.updated')).to be_empty
  end

  it 'rejects invalid priority in writes and filters' do
    patch endpoint, params: { project: { priority: 'invalid', lock_version: project.lock_version } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(project.reload.priority).to eq('medium')
    get collection, params: { priority: 'invalid' }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'calculates progress from the existing tasks rather than a writable project percentage' do
    column = project.board_columns.find_by!(status_key: 'backlog')
    project.tasks.create!(account: account, created_by: owner, title: 'Pending', board_column: column, status: 'backlog')
    done_column = project.board_columns.find_by!(status_key: 'completed')
    project.tasks.create!(account: account, created_by: owner, title: 'Done', board_column: done_column, status: 'completed')
    get endpoint, headers: headers
    expect(response.parsed_body.fetch('data')).to include('tasks_total' => 2, 'tasks_completed' => 1, 'progress' => 50)
  end
end
