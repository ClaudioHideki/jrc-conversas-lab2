require 'rails_helper'

RSpec.describe JrcNico::DomainActions do
  include_context 'JRC Service Desk domain'

  let(:access) { JrcNico::OperationalAccess.new(account: sd_account, user: sd_user) }
  let(:session) { JrcNico::Session.create!(account: sd_account, user: sd_user) }
  let(:command) { session.commands.create!(request_id: SecureRandom.uuid, message: 'Operação local de teste') }
  let(:executor) { JrcNico::ToolExecutor.new(access, command: command) }
  let(:project) do
    JrcProjects::Projects::Create.call(account: sd_account, actor: sd_user, attributes: { name: 'Delivery' }, idempotency_key: SecureRandom.uuid)
  end

  before do
    sd_account.update!(custom_attributes: { 'nico_enabled' => true })
    sd_account.enable_features!('jrc_projects')
    sd_account_user.update!(jrc_projects_enabled: true)
  end

  it 'creates a real R2 ticket once per command and preserves its unit and requester' do
    arguments = sd_create_attributes.stringify_keys.merge('unit_id' => sd_unit.id)
    first = executor.call('create_service_ticket', arguments)
    expect { executor.call('create_service_ticket', arguments) }.not_to change(JrcServiceDesk::Ticket, :count)
    ticket = JrcServiceDesk::Ticket.find(first.dig(:record, 'id'))
    expect(ticket).to have_attributes(unit_id: sd_unit.id, requester_id: sd_contact.id, idempotency_key: "nico_#{command.id}_#{command.request_id}")
    expect do
      executor.call('create_service_ticket', arguments.merge('title' => 'Different request'))
    end.to raise_error(JrcServiceDesk::IdempotencyConflict)
  end

  it 'rejects foreign-unit references without creating a ticket' do
    foreign_priority = create(:jrc_sd_priority, unit: sd_foreign_unit)
    arguments = sd_create_attributes.stringify_keys.merge('unit_id' => sd_unit.id, 'priority_id' => foreign_priority.id)
    expect { executor.call('create_service_ticket', arguments) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcServiceDesk::Ticket.where(account: sd_account)).to be_empty
  end

  it 'accepts version zero and preserves the native optimistic lock on a repeated R2 edit' do
    ticket = sd_ticket
    arguments = { 'ticket_id' => ticket.id, 'expected_lock_version' => ticket.lock_version, 'title' => 'Reviewed title' }
    operator = JrcNico::OperatorSession.new(account: sd_account, user: sd_user)
    prepared = operator.ask(message: 'Review version zero ticket', request_id: SecureRandom.uuid,
                            prepared: { 'tool' => 'update_service_ticket', 'arguments' => arguments })
    operator.execute(prepared)
    expect(prepared.reload.status).to eq('succeeded')
    expect(ticket.reload.title).to eq('Reviewed title')
    executed = JrcNico::ToolExecutor.new(access, command: prepared)
    expect { executed.call('update_service_ticket', arguments.merge('title' => 'Stale overwrite')) }.to raise_error(ActiveRecord::StaleObjectError)
    expect(ticket.reload.title).to eq('Reviewed title')
  end

  it 'rechecks R2 membership after the command was prepared' do
    ticket = sd_ticket
    command
    sd_membership.update!(active: false)
    expect { executor.call('read_service_ticket', { 'ticket_id' => ticket.id }) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'keeps page metadata but omits aggregate totals outside the returned resource manifest' do
    ticket = sd_ticket
    tickets = executor.call('list_service_tickets', {})
    lookup = executor.call('service_desk_lookup', { 'resource' => 'priorities', 'unit_id' => sd_unit.id })
    lifecycle = executor.call('read_service_ticket_lifecycle', { 'ticket_id' => ticket.id })
    links = executor.call('read_operation_links', { 'project_id' => project.id })

    expect(tickets[:items].length).to eq(1)
    expect(tickets[:meta]).to eq(page: 1, per_page: 20)
    expect(lookup[:meta]).to eq(page: 1, per_page: 20)
    expect(lifecycle.dig(:details, :meta)).to eq(page: 1, per_page: 20)
    expect(links.keys & %i[tickets_total projects_total]).to be_empty
    expect(JrcServiceDesk::TicketQuery.new(user_context: sd_context).collection[:meta][:total]).to eq(1)
  end

  %w[assign_service_ticket transfer_service_ticket].each do |tool|
    it "acknowledges #{tool} when handing off the ticket removes the actor's read scope" do
      target_member = create(:account_user, account: sd_account, user: create(:user), role: :agent)
      target_grant = create(:jrc_sd_membership, unit: sd_unit, account_user: target_member)
      ticket = create(:jrc_sd_ticket, unit: sd_unit, requester: sd_contact, status: sd_status, priority: sd_priority,
                                      created_by_membership: target_grant, assignee_membership: sd_membership)
      operator = JrcNico::OperatorSession.new(account: sd_account, user: sd_user)
      prepared = operator.ask(message: 'Hand off reviewed ticket', request_id: SecureRandom.uuid,
                              prepared: { 'tool' => tool, 'arguments' => { 'ticket_id' => ticket.id, 'expected_lock_version' => ticket.lock_version,
                                                                           'assignee_account_user_id' => target_member.id } })

      operator.execute(prepared)

      expect(prepared.reload.status).to eq('succeeded')
      expect(ticket.reload.assignee_membership_id).to eq(target_grant.id)
      expect(prepared.result.fetch('record')).to eq('id' => ticket.id, 'applied' => true)
      expect(JrcServiceDesk::TicketPolicy.new(sd_context, ticket).show?).to be(false)
    end
  end

  it 'requires a persisted operator command for idempotent creation and rejects an injected request key' do
    arguments = sd_create_attributes.stringify_keys.merge('unit_id' => sd_unit.id)
    expect { JrcNico::ToolExecutor.new(access).call('create_service_ticket', arguments) }.to raise_error(ArgumentError, /comando NICO/)
    expect { executor.call('create_service_ticket', arguments.merge('idempotency_key' => 'model-key')) }.to raise_error(ArgumentError, /Campo/)
  end

  it 'requires an explicit unit grant for admin ticket execution and saved-result access' do
    ticket = sd_ticket
    sd_as_admin!
    sd_membership.update!(active: false)
    expect { executor.call('read_service_ticket', { 'ticket_id' => ticket.id }) }.to raise_error(ActiveRecord::RecordNotFound)

    sd_membership.update!(active: true)
    result = executor.call('read_service_ticket', { 'ticket_id' => ticket.id })
    expect(result[:resources]).to include(['JrcServiceDesk::Ticket', ticket.id])
    expect(JrcNico::DomainAccess.authorize_resource!(access, 'JrcServiceDesk::Ticket', ticket.id)).to eq(ticket)

    sd_membership.update!(active: false)
    expect { executor.call('read_service_ticket', { 'ticket_id' => ticket.id }) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { JrcNico::DomainAccess.authorize_resource!(access, 'JrcServiceDesk::Ticket', ticket.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'creates a project idempotently and applies native completion requirements' do
    created = executor.call('create_project', { 'name' => 'Native delivery' })
    expect { executor.call('create_project', { 'name' => 'Native delivery' }) }.not_to change(JrcProjects::Project, :count)
    row = JrcProjects::Project.find(created.dig(:record, 'id'))
    expect do
      executor.call('update_project', { 'project_id' => row.id, 'lock_version' => row.lock_version, 'status' => 'completed' })
    end.to raise_error(ArgumentError, /aceite/)
    expect(row.reload.status).to eq('planned')
  end

  it 'hides projects after revocation and rejects projects from another account' do
    project
    stranger = create(:account)
    other = create(:user, account: stranger, role: :administrator)
    stranger.enable_features!('jrc_projects')
    foreign = JrcProjects::Projects::Create.call(account: stranger, actor: other, attributes: { name: 'Foreign' }, idempotency_key: SecureRandom.uuid)
    expect { executor.call('read_project', { 'project_id' => foreign.id }) }.to raise_error(ActiveRecord::RecordNotFound)
    catalog = JrcNico::ToolCatalog.new(access)
    expect(catalog.available.pluck(:name)).to include('read_project', 'create_project')
    sd_account_user.update!(jrc_projects_enabled: false)
    expect(catalog.available.pluck(:name)).not_to include('read_project', 'create_project')
  end

  it 'returns the native agenda limitation and bounded filters without inventing R2 tasks' do
    result = executor.call('read_operations_agenda', { 'source' => 'service_desk', 'from' => '2026-09-01', 'to' => '2026-09-30' })
    expect(result[:data]).to eq([])
    expect(result.dig(:meta, :unavailable_sources, :service_desk)).to eq('native_tasks_not_available')
    expect do
      executor.call('read_operations_agenda', { 'from' => '2025-01-01', 'to' => '2026-09-30' })
    end.to raise_error(ArgumentError, /366/)
  end

  it 'does not expose controller-only mutations or accept arbitrary dispatch names' do
    names = JrcNico::ToolCatalog.new(access).available.pluck(:name)
    expect(names).not_to include('pay_commission', 'send_contract_for_signature', 'update_sales_order')
    expect { executor.call('destroy_all', {}) }.to raise_error(Pundit::NotAuthorizedError)
    expect do
      executor.call('update_project', { 'project_id' => project.id, 'lock_version' => -1, 'name' => 'Invalid' })
    end.to raise_error(ArgumentError, /lock_version/)
  end

  it 'keeps new domain commands outside customer-request and delegated execution' do
    notice = JrcNico::Notice.create!(account: sd_account, user: sd_user, event_key: SecureRandom.uuid,
                                     kind: 'action', status: 'new', body: 'Customer request')
    command.update!(source_notice: notice)
    expect { executor.call('read_operations_agenda', {}) }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcNico::DelegatedActions::GROUPS.values.flatten & JrcNico::DomainToolCatalog::TOOLS.keys).to be_empty
    expect {
      executor.call('create_project_task', { 'project_id' => project.id, 'board_column_id' => project.board_columns.first!.id,
                                             'title' => 'Denied' })
    }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcNico::DelegatedActions::GROUPS.values.flatten & JrcNico::ModuleActions::PROJECT_TASK_TOOLS).to be_empty
  end

  it 'revalidates R2 and project resource references before exposing saved results' do
    ticket = sd_ticket
    project
    expect(JrcNico::DomainAccess.authorize_resource!(access, 'JrcServiceDesk::Ticket', ticket.id)).to eq(ticket)
    sd_membership.update!(active: false)
    expect { JrcNico::DomainAccess.authorize_resource!(access, 'JrcServiceDesk::Ticket', ticket.id) }.to raise_error(ActiveRecord::RecordNotFound)
    sd_account_user.update!(jrc_projects_enabled: false)
    expect { JrcNico::DomainAccess.authorize_resource!(access, 'JrcProjects::Project', project.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'keeps project details bounded and removes a linked contact denied by its own policy' do
    project.update!(contact: sd_contact)
    allow(access).to receive(:policy).and_call_original
    allow(access).to receive(:policy).with(sd_contact).and_return(instance_double(ContactPolicy, show?: false))

    result = executor.call('read_project', { 'project_id' => project.id })

    expect(result[:record]).not_to have_key('contact')
    expect(result[:record]).not_to have_key('contact_id')
    expect(result[:record].keys & %w[budget recent_activity members overview]).to be_empty
    expect(result[:record]['columns'].length).to eq(4)
    expect(result[:resources]).not_to include(['Contact', sd_contact.id])
  end

  it 'records linked contacts in project list provenance and rechecks the additional task-read grant' do
    project.update!(contact: sd_contact)
    result = executor.call('list_projects', {})
    expect(result[:resources]).to include(['Contact', sd_contact.id], ['JrcNico::ProjectTasks', project.id])

    role = create(:custom_role, account: sd_account, permissions: ['jrc_projects_project_view'])
    sd_account_user.update!(custom_role_id: role.id)
    expect(JrcNico::DomainAccess.authorize_resource!(access, 'JrcProjects::Project', project.id)).to eq(project)
    expect { JrcNico::DomainAccess.authorize_resource!(access, 'JrcNico::ProjectTasks', project.id) }.to raise_error(Pundit::NotAuthorizedError)

    data = executor.call('read_project', { 'project_id' => project.id })[:record]
    expect(data.keys & %w[tasks_total tasks_completed progress columns]).to be_empty
  end

  it 'records requester and SLA grants separately from ticket read access' do
    ticket = sd_ticket
    result = executor.call('list_service_tickets', {})
    expect(result[:resources]).to include(['Contact', sd_contact.id], ['JrcNico::ServiceTicketCustomer', ticket.id],
                                          ['JrcNico::ServiceTicketSla', ticket.id])

    role = create(:custom_role, account: sd_account, permissions: %w[jrc_service_desk_module_view jrc_service_desk_tickets_view])
    sd_account_user.update!(custom_role_id: role.id)
    expect(JrcNico::DomainAccess.authorize_resource!(access, 'JrcServiceDesk::Ticket', ticket.id)).to eq(ticket)
    expect { JrcNico::DomainAccess.authorize_resource!(access, 'JrcNico::ServiceTicketSla', ticket.id) }.to raise_error(Pundit::NotAuthorizedError)
    expect {
      JrcNico::DomainAccess.authorize_resource!(access, 'JrcNico::ServiceTicketCustomer', ticket.id)
    }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'revalidates a link source even when it has no related records' do
    result = executor.call('read_operation_links', { 'project_id' => project.id })
    expect(result[:relations]).to be_empty
    expect(result[:resources]).to include(['JrcProjects::Project', project.id])
    sd_account_user.update!(jrc_projects_enabled: false)
    expect { JrcNico::DomainAccess.authorize_resource!(access, *result[:resources].first) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'redacts linked R2 requester data and revalidates its independent customer grant' do
    ticket = sd_ticket
    executor.call('link_project_record', { 'project_id' => project.id, 'ticket_id' => ticket.id })
    result = executor.call('read_operation_links', { 'project_id' => project.id })
    expect(result[:resources]).to include(['JrcNico::ServiceTicketCustomer', ticket.id], ['Contact', sd_contact.id])
    expect(result[:relations].first.fetch(:contact)).to include('id' => sd_contact.id, 'name' => sd_contact.name)

    role = create(:custom_role, account: sd_account,
                                permissions: %w[jrc_projects_project_view jrc_service_desk_module_view jrc_service_desk_tickets_view])
    sd_account_user.update!(custom_role_id: role.id)
    expect(JrcNico::DomainAccess.authorize_resource!(access, 'JrcServiceDesk::Ticket', ticket.id)).to eq(ticket)
    expect {
      JrcNico::DomainAccess.authorize_resource!(access, 'JrcNico::ServiceTicketCustomer', ticket.id)
    }.to raise_error(Pundit::NotAuthorizedError)

    redacted = executor.call('read_operation_links', { 'project_id' => project.id })
    expect(redacted[:tickets].first).not_to have_key('requester_id')
    expect(redacted[:relations].first.fetch(:ticket)).not_to have_key('requester_id')
    expect(redacted[:relations].first).not_to have_key(:contact)
    expect(redacted[:resources]).not_to include(['Contact', sd_contact.id])
    expect(redacted.to_json).not_to include(sd_contact.name)
  end

  it 'redacts ticket conversation links and hides their saved history after the R2 grant is revoked' do
    ticket = sd_ticket
    conversation = create(:conversation, account: sd_account, contact: sd_contact)
    create(:inbox_member, inbox: conversation.inbox, user: sd_user)
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
    executor.call('link_project_record', { 'project_id' => project.id, 'ticket_id' => ticket.id })
    command.update!(status: 'succeeded')
    operator = JrcNico::OperatorSession.new(account: sd_account, user: sd_user)
    allow(JrcNico::OperationalInference).to receive(:call).and_return(
      { 'tool' => 'read_operation_links', 'arguments' => { 'ticket_id' => ticket.id }, 'reply' => '' },
      { 'tool' => '', 'arguments' => {}, 'reply' => 'Restricted ticket conversation association' }
    )
    operator.ask(message: 'Read ticket links', request_id: SecureRandom.uuid)
    expect(operator.session.reload.context.fetch('resources')).to include(['JrcNico::ServiceTicketConversations', ticket.id])
    expect(operator.session.context.fetch('conversation_ids')).to include(conversation.display_id)

    role = create(:custom_role, account: sd_account,
                                permissions: %w[conversation_manage jrc_projects_project_view
                                                jrc_service_desk_module_view jrc_service_desk_tickets_view])
    sd_account_user.update!(custom_role_id: role.id)
    expect(access.authorize!.conversation(conversation.display_id)).to eq(conversation)
    expect(JrcNico::DomainAccess.authorize_resource!(access, 'JrcServiceDesk::Ticket', ticket.id)).to eq(ticket)
    expect {
      JrcNico::DomainAccess.authorize_resource!(access, 'JrcNico::ServiceTicketConversations', ticket.id)
    }.to raise_error(Pundit::NotAuthorizedError)

    redacted = executor.call('read_operation_links', { 'ticket_id' => ticket.id })
    expect(redacted[:conversations]).to be_empty
    expect(redacted[:conversation_ids]).to be_empty
    expect(redacted[:relations].first).not_to have_key(:conversation)
    expect(JrcNico::OperatorSession.new(account: sd_account, user: sd_user).session.messages).to be_empty
  end

  it 'removes links idempotently through the native service without deleting the source records' do
    ticket = sd_ticket
    linked = executor.call('link_project_record', { 'project_id' => project.id, 'ticket_id' => ticket.id })
    arguments = { 'link_id' => linked.dig(:record, 'id'), 'project_id' => project.id }
    expect { executor.call('unlink_project_record', arguments) }.to change(JrcOperations::Link, :count).by(-1)
    expect { executor.call('unlink_project_record', arguments) }.not_to change(JrcProjects::AuditEvent, :count)
    expect(ticket.reload).to be_persisted
    expect(project.reload).to be_persisted
  end

  it 'creates a real task through the native service in the explicit project column' do
    result = nil
    column = project.board_columns.find_by!(status_key: 'backlog')
    arguments = { 'project_id' => project.id, 'board_column_id' => column.id, 'title' => 'Reviewed task', 'estimated_minutes' => 0 }
    expect { result = executor.call('create_project_task', arguments) }.to change(JrcProjects::Task, :count).by(1)
    task = project.tasks.find(result.dig(:record, 'id'))
    expect(task).to have_attributes(title: 'Reviewed task', estimated_minutes: 0, board_column_id: column.id, created_by_id: sd_user.id)
    expect(result).to include(resource_type: 'JrcProjects::Task')
    expect(result).not_to have_key(:browser_action)
    expect(result[:resources]).to include(['JrcProjects::Project', project.id], ['JrcNico::ProjectTasks', project.id], ['JrcProjects::Task', task.id])
    expect do
      executor.call('create_project_task', arguments.merge('status' => 'completed'))
    end.to raise_error(ArgumentError, /Campo/)
  end

  it 'uses task scope, native write capability and a reviewed version before a browser edit' do
    task = project.tasks.create!(account: sd_account, created_by: sd_user, board_column: project.board_columns.first!, status: 'backlog',
                                 title: 'Original')
    arguments = { 'project_id' => project.id, 'task_id' => task.id, 'lock_version' => 0, 'title' => 'Reviewed' }
    result = executor.call('update_project_task', arguments)
    expect(result[:parameters]['lock_version']).to eq(0)
    expect(task.reload.title).to eq('Original')
    expect(result[:resources]).to include(['JrcProjects::Task', task.id])
    expect do
      executor.call('update_project_task', arguments.merge('assignee_id' => sd_user.id, 'clear_assignee' => true))
    end.to raise_error(ArgumentError, /definir ou remover/)
    role = create(:custom_role, account: sd_account, permissions: %w[jrc_projects_project_view jrc_projects_task_view])
    sd_account_user.update!(custom_role_id: role.id)
    expect { executor.call('update_project_task', arguments) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'claims a browser task edit only once and blocks replay after an unknown outcome' do
    operator = JrcNico::OperatorSession.new(account: sd_account, user: sd_user)
    task = project.tasks.create!(account: sd_account, created_by: sd_user, board_column: project.board_columns.first!, status: 'backlog',
                                 title: 'Original')
    prepared = operator.ask(message: 'Edit reviewed task', request_id: SecureRandom.uuid,
                            prepared: { 'tool' => 'update_project_task', 'arguments' => { 'project_id' => project.id, 'task_id' => task.id,
                                                                                          'lock_version' => task.lock_version,
                                                                                          'title' => 'Reviewed task' } })
    expect { operator.execute(prepared) }.not_to change(JrcProjects::Task, :count)
    expect(prepared.reload.status).to eq('browser_pending')
    operator.browser_claim(prepared)
    expect { operator.browser_claim(prepared) }.to raise_error(JrcNico::OperatorSession::Busy)
    operator.browser_result(prepared, 'unknown', 'Confira o projeto antes de repetir.')
    expect { operator.execute(prepared) }.not_to change(JrcProjects::Task, :count)
    expect(prepared.reload.status).to eq('unknown')
    expect { operator.browser_claim(prepared) }.to raise_error(JrcNico::OperatorSession::Busy)
  end

  it 'revalidates project grants before creating an already prepared native task command' do
    operator = JrcNico::OperatorSession.new(account: sd_account, user: sd_user)
    prepared = operator.ask(message: 'Create reviewed task', request_id: SecureRandom.uuid,
                            prepared: { 'tool' => 'create_project_task', 'arguments' => { 'project_id' => project.id,
                                                                                          'board_column_id' => project.board_columns.first!.id,
                                                                                          'title' => 'Reviewed task' } })
    sd_account_user.update!(jrc_projects_enabled: false)
    expect { operator.execute(prepared) }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcProjects::Task.where(project: project)).to be_empty
    expect(prepared.reload.status).to eq('failed')
  end

  it 'revalidates native Contact receipts in the current Account and rejects a foreign Account contact' do
    foreign = create(:contact, account: sd_foreign_account)
    expect(JrcNico::DomainAccess.authorize_resource!(access, 'Contact', sd_contact.id)).to eq(sd_contact)
    expect do
      JrcNico::DomainAccess.authorize_resource!(access, 'Contact', foreign.id)
    end.to raise_error(ActiveRecord::RecordNotFound)
    sd_account.update!(custom_attributes: { 'nico_enabled' => false })
    expect do
      JrcNico::DomainAccess.authorize_resource!(access, 'Contact', sd_contact.id)
    end.to raise_error(Pundit::NotAuthorizedError)
  end
end
