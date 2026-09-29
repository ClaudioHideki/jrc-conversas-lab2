require 'rails_helper'

RSpec.describe 'Projects linked exclusively to Service Desk R2', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: agent) }
  let(:admin_member) { account.account_users.find_by!(user: admin) }
  let(:operator) { create(:jrc_sd_operator_company, account: account) }
  let(:unit) { create(:jrc_sd_unit, operator_company: operator) }
  let(:other_unit) { create(:jrc_sd_unit, operator_company: operator) }
  let(:grant) { create(:jrc_sd_membership, unit: unit, account_user: member) }
  let(:contact) { create(:contact, account: account) }
  let(:ticket) { create(:jrc_sd_ticket, unit: unit, requester: contact, created_by_membership: grant) }
  let(:other_ticket) { create(:jrc_sd_ticket, unit: other_unit, requester: contact) }
  let(:project) do
    JrcProjects::Projects::Create.call(account: account, actor: agent, attributes: { name: 'R2 delivery', contact_id: contact.id }, idempotency_key: SecureRandom.uuid)
  end
  let(:url) { "/api/v1/accounts/#{account.id}/operations/links" }
  let(:headers) { agent.create_new_auth_token.merge('X-Request-Id' => 'r2-project-link') }
  let(:context) { { account: account, user: admin, account_user: admin_member } }

  before do
    account.enable_features!('jrc_projects', 'jrc_service_desk')
    member.update!(jrc_projects_enabled: true)
  end

  it 'creates a project from a ticket with replay, preserving ticket identity and customer' do
    path = "/api/v1/accounts/#{account.id}/projects/projects"
    key = SecureRandom.uuid
    id = ticket.id
    2.times do
      post path, params: { project: { name: 'Delivery from ticket' }, ticket_id: id }, headers: headers.merge('Idempotency-Key' => key), as: :json
      expect(response).to have_http_status(:created)
    end
    expect(JrcProjects::Project.where(account: account).count).to eq(1)
    link = JrcOperations::Link.find_by!(ticket_id: id)
    expect(link.ticket).to be_a(JrcServiceDesk::Ticket)
    expect(link.project.contact_id).to eq(contact.id)
    expect(link.ticket_unit_id).to eq(unit.id)
    expect(ticket.reload.status.phase).to eq('open')
    grant.update!(active: false)
    post path, params: { project: { name: 'Delivery from ticket' }, ticket_id: id }, headers: headers.merge('Idempotency-Key' => key), as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'links a task idempotently, returns both navigable records and unlinks without deleting either' do
    task = project.tasks.create!(account: account, created_by: agent, title: 'Execution', board_column: project.board_columns.first!)
    2.times do
      post url, params: { project_id: project.id, ticket_id: ticket.id, task_id: task.id }, headers: headers, as: :json
      expect(response).to have_http_status(:created)
    end
    link = JrcOperations::Link.find(response.parsed_body.dig('data', 'id'))
    expect(JrcOperations::Link.count).to eq(1)
    get url, params: { ticket_id: ticket.id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'relations', 0, 'project', 'id')).to eq(project.id)
    get url, params: { project_id: project.id }, headers: headers
    expect(response.parsed_body.dig('data', 'relations', 0, 'ticket', 'id')).to eq(ticket.id)
    delete "#{url}/#{link.id}", params: { project_id: project.id }, headers: headers, as: :json
    expect(response).to have_http_status(:no_content)
    expect(JrcServiceDesk::Ticket.exists?(ticket.id)).to be(true)
    expect(JrcProjects::Task.exists?(task.id)).to be(true)
    expect(JrcProjects::AuditEvent.where(action: 'projects.link.removed').last.correlation_id).to eq('r2-project-link')
    delete "#{url}/#{link.id}", params: { project_id: project.id }, headers: headers, as: :json
    expect(response).to have_http_status(:no_content)
    expect(JrcProjects::AuditEvent.where(action: 'projects.link.removed').count).to eq(1)
    grant.update!(active: false)
    delete "#{url}/#{link.id}", params: { project_id: project.id }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'never grants ticket access through project membership or across a second unit/account' do
    foreign = create(:jrc_sd_ticket)
    [other_ticket, foreign].each do |outside|
      post url, params: { project_id: project.id, ticket_id: outside.id }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
    JrcOperations::Link.create!(account: account, created_by: admin, project: project, ticket: other_ticket)
    get url, params: { project_id: project.id }, headers: headers
    expect(response.parsed_body.dig('data', 'tickets')).to be_empty
    expect(response.parsed_body.dig('data', 'relations')).to be_empty
    expect(JrcServiceDesk::UnitMembership.where(account_user: member, unit: other_unit)).to be_empty
  end

  it 'rejects a mismatched contact and a task belonging to another project' do
    project.update!(contact: create(:contact, account: account))
    post url, params: { project_id: project.id, ticket_id: ticket.id }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcOperations::Link.count).to eq(0)
    other = JrcProjects::Projects::Create.call(account: account, actor: agent, attributes: { name: 'Other' }, idempotency_key: SecureRandom.uuid)
    task = other.tasks.create!(account: account, created_by: agent, title: 'Other task', board_column: other.board_columns.first!)
    post url, params: { project_id: project.id, ticket_id: ticket.id, task_id: task.id }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'uses native TicketConversation and resolves conversation display IDs independently' do
    conversation = create(:conversation, account: account, contact: contact, display_id: 90807)
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation, linked_by_membership: grant)
    post url, params: { project_id: project.id, conversation_display_id: conversation.display_id }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created)
    expect(JrcOperations::Link.last.conversation_id).to eq(conversation.id)
    post url, params: { ticket_id: ticket.id, conversation_display_id: conversation.display_id }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(ticket.ticket_conversations.count).to eq(1)
  end

  it 'gives admin a view of all own units without operational memberships' do
    ticket; other_ticket
    native = JrcServiceDesk::OperationalContext.new(context)
    expect(native.unit_scope).to be_empty
    expect(native.view_unit_scope).to contain_exactly(unit, other_unit)
    expect(JrcServiceDesk::TicketPolicy::Scope.new(context, JrcServiceDesk::Ticket).resolve).to contain_exactly(ticket, other_ticket)
    expect(JrcServiceDesk::TicketPolicy.new(context, ticket).update?).to be(false)
    expect(JrcServiceDesk::UnitMembership.where(account_user: admin_member)).to be_empty
    create(:jrc_sd_membership, unit: unit, account_user: admin_member)
    expect(JrcServiceDesk::TicketPolicy.new(context, ticket).update?).to be(true)
    expect(JrcServiceDesk::TicketPolicy.new(context, other_ticket).update?).to be(false)
  end

  it 'lets admin configure a unit and grant agent scope without creating an admin operational membership' do
    result = JrcServiceDesk::ConfigurationService.new(user_context: context).create(
      resource: 'categories', unit_id: unit.id, attributes: { code: 'new-category', name: 'Delivery', active: true }, idempotency_key: SecureRandom.uuid
    )
    expect(result.record.unit_id).to eq(unit.id)
    expect(JrcServiceDesk::StructureContext.new(context).allowed?('unit_memberships')).to be(true)
    expect(JrcServiceDesk::UnitMembership.where(account_user: admin_member)).to be_empty
  end

  it 'enforces the ticket unit boundary in PostgreSQL even if model validations are bypassed' do
    link = JrcOperations::Link.create!(account: account, created_by: agent, project: project, ticket: ticket)
    outside_id = other_unit.id
    expect do
      JrcOperations::Link.transaction(requires_new: true) { link.update_columns(ticket_unit_id: outside_id) }
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(link.reload.ticket_unit_id).to eq(unit.id)
  end

  it 'rolls back the link when its audit cannot be persisted' do
    project; ticket
    allow(JrcProjects::AuditEvent).to receive(:record!).and_raise(ActiveRecord::RecordInvalid.new(JrcProjects::AuditEvent.new))
    expect do
      JrcOperations::Linker.new(account_user: member).create!(attributes: { project_id: project.id, ticket_id: ticket.id })
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(JrcOperations::Link.where(account: account)).to be_empty
  end
end
