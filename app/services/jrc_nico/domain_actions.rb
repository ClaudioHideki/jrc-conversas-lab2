# Each command delegates to a native domain service or an authorized read scope.
# Mutations whose rules exist only in controllers are deliberately not implemented here.
class JrcNico::DomainActions
  CRM_READS = {
    'sales_order' => [JrcCrm::SalesOrder, :owner_id, %w[id order_number status contact_id owner_id deal_id proposal_id total_cents monthly_cents sold_at]],
    'contract' => [JrcCrm::Contract, :owner_id, %w[id contract_number status sales_order_id contact_id owner_id starts_on ends_on monthly_cents signature_mode signature_status]],
    'commission' => [JrcCrm::SalesCommission, :user_id, %w[id sales_order_id user_id status base_cents rate_percent commission_cents released_at paid_at]],
    'backoffice_request' => [JrcCrm::BackofficeRequest, :owner_id, %w[id title status stage priority sales_order_id contract_id owner_id due_at]]
  }.freeze

  def initialize(access, command: nil)
    @access = access.authorize!
    @domain = JrcNico::DomainAccess.new(@access)
    @command = command
  end

  def call(name, arguments)
    raise ArgumentError, 'Operação não disponível.' unless JrcNico::DomainToolCatalog::TOOLS.key?(name)

    @args = arguments
    case name
    when 'list_relationship_portfolio' then relationship_portfolio
    when 'read_relationship_customer' then relationship_customer
    when 'service_desk_context' then service_desk_context
    when 'service_desk_lookup' then service_desk_lookup
    when 'list_service_tickets' then list_service_tickets
    when 'read_service_ticket' then ticket_result(@domain.ticket(@args.fetch('ticket_id')))
    when 'create_service_ticket' then create_service_ticket
    when 'update_service_ticket', 'assign_service_ticket', 'transfer_service_ticket' then change_service_ticket(name)
    when 'add_service_ticket_note' then add_service_ticket_note
    when 'read_service_ticket_lifecycle' then read_service_ticket_lifecycle
    when 'transition_service_ticket' then transition_service_ticket
    when 'link_service_ticket_conversation' then link_service_ticket_conversation
    when 'list_projects' then list_projects
    when 'read_project' then project_result(@domain.project(@args.fetch('project_id')), details: true)
    when 'list_project_tasks' then list_project_tasks
    when 'read_project_task' then task_result(@domain.task(@args.fetch('project_id'), @args.fetch('task_id')))
    when 'create_project' then create_project
    when 'create_project_task' then create_project_task
    when 'update_project' then update_project
    when 'move_project_task' then move_project_task
    when 'read_operations_agenda' then read_operations_agenda
    when 'read_operation_links' then read_operation_links
    when 'link_project_record' then link_project_record
    when 'unlink_project_record' then unlink_project_record
    when 'list_sales_orders' then crm_list('sales_order')
    when 'read_sales_order' then crm_read('sales_order')
    when 'list_contracts' then crm_list('contract')
    when 'read_contract' then crm_read('contract')
    when 'list_commissions' then crm_list('commission')
    when 'list_backoffice_requests' then crm_list('backoffice_request')
    when 'read_backoffice_request' then crm_read('backoffice_request')
    when 'convert_proposal_to_order' then convert_proposal_to_order
    when 'list_sales_goals' then list_sales_goals
    when 'list_commission_programs' then list_commission_programs
    end
  end

  private

  def context
    @domain.context
  end

  def request_key
    unless @command&.persisted? && @command.session.account_id == @access.account.id && @command.session.user_id == @access.user.id && @command.request_id.present?
      raise ArgumentError, 'Prepare um comando NICO antes desta operação.'
    end
    "nico_#{@command.id}_#{@command.request_id}"
  end

  def presenter
    @presenter ||= JrcServiceDesk::Presenter.new(user_context: context)
  end

  def relationship_customer
    ctx = JrcRelationship::Context.new(@access.membership)
    assignment = ctx.assignment(@args.fetch('assignment_id'))
    relation = JrcRelationship::HealthSnapshot.where(assignment: assignment, viewer: ctx.user, access_signature: ctx.access_signature)
    snapshot = JrcRelationship::SnapshotAccess.scope(ctx, relation).order(:id).last
    signals = snapshot&.signals&.deep_symbolize_keys || { health: { score: nil, band: 'unavailable', factors: [] } }
    risks = ctx.records(JrcRelationship::RiskCase).where(assignment: assignment).where.not(status: %w[retained churn no_action]).limit(10)
    actions = ctx.records(JrcRelationship::Action).where(assignment: assignment, status: JrcRelationship::Action::ACTIVE_STATUSES).order(priority: :desc).limit(10)
    plans = ctx.records(JrcRelationship::SuccessPlan).where(assignment: assignment).limit(10)
    qbrs = ctx.records(JrcRelationship::Qbr).where(assignment: assignment).order(scheduled_at: :desc).limit(10)
    work_context = JrcRelationship::WorkContext.new(context: ctx, assignment: assignment).call
    sources = JrcRelationship::SnapshotAccess.sources(ctx)
    evidence_resources = work_context.fetch(:_source_ids).flat_map do |key, ids|
      next [] if Array(ids).empty?
      native = sources.fetch(key.to_s)
      Array(ids).map { |id| [native.klass.name, id] }
    end
    { customer: assignment.label, health: signals[:health], signals: signals.except(:_source_ids),
      risks: risks.as_json(only: [:id, :kind, :severity, :reason, :status, :due_at]),
      actions: actions.as_json(only: [:id, :kind, :reason, :priority, :due_at]),
      plans: plans.as_json(only: [:id, :title, :status, :goals, :target_on]),
      qbrs: qbrs.as_json(only: [:id, :title, :scheduled_at, :agenda, :summary, :decisions]),
      qbr_context: work_context.except(:_source_ids),
      calculated_at: snapshot&.calculated_at, external_actions_require_confirmation: true,
      resources: [[assignment.class.name, assignment.id]] + (snapshot ? [[snapshot.class.name, snapshot.id]] : []) +
        risks.map { |row| [row.class.name, row.id] } + actions.map { |row| [row.class.name, row.id] } +
        plans.map { |row| [row.class.name, row.id] } + qbrs.map { |row| [row.class.name, row.id] } + evidence_resources }
  end

  def relationship_portfolio
    ctx = JrcRelationship::Context.new(@access.membership)
    scope = ctx.assignments
    if @args['query'].present?
      query = "%#{ActiveRecord::Base.sanitize_sql_like(@args['query'])}%"
      scope = scope.left_joins(:company, :contact).where('companies.name ILIKE :q OR contacts.name ILIKE :q', q: query)
    end
    page = @args.fetch('page', 1).to_i.clamp(1, 20)
    rows = scope.includes(:company, :contact, :owner).order(:id).offset((page - 1) * 20).limit(20)
    actions = ctx.records(JrcRelationship::Action).where(assignment_id: rows.map(&:id), status: JrcRelationship::Action::ACTIVE_STATUSES)
      .order(priority: :desc, due_at: :asc, id: :asc).limit(20)
    { customers: rows.map { |row| { assignment_id: row.id, name: row.label, owner: row.owner&.name, status: row.status } },
      priority_actions: actions.as_json(only: [:id, :assignment_id, :kind, :reason, :priority, :due_at, :factors]), page: page,
      resources: rows.map { |row| [row.class.name, row.id] } + actions.map { |row| [row.class.name, row.id] } }
  end

  def service_desk_context
    result = JrcServiceDesk::UiContextService.new(user_context: context).call
    resources = [['JrcNico::ServiceDeskContext', @access.account.id]]
    result[:units].each do |unit|
      resources << ['JrcNico::ServiceDeskUnit', unit[:id].to_i]
      resources << ['JrcServiceDesk::TicketStatus', unit[:initial_status][:id].to_i] if unit[:initial_status]
    end
    result.merge(resources: resources)
  end

  def receipt(record, data, message: nil, route: nil)
    { resource_type: record.class.name, record: data.stringify_keys.merge('id' => record.id), message: message, route_name: route }.compact
  end

  def ticket_result(ticket, message: nil)
    data = presenter.ticket(ticket)
    resources = [[ticket.class.name, ticket.id]]
    resources << ['JrcNico::ServiceTicketSla', ticket.id] if data[:sla]
    resources += [['Contact', ticket.requester_id], ['JrcNico::ServiceTicketCustomer', ticket.id]] if data[:requester]
    resources << ['Team', ticket.team_id] if data[:team]
    resources << ['JrcNico::ServiceDeskAssignee', ticket.assignee_membership_id] if data[:assignee]
    receipt(ticket, data, message: message, route: 'jrc_service_desk_tickets').merge(resources: resources)
  end

  def list_service_tickets
    result = JrcServiceDesk::TicketQuery.new(user_context: context, parameters: @args).collection
    collection(result[:items].map { |ticket| ticket_result(ticket) }).merge(meta: result[:meta].except(:total))
  end

  def service_desk_lookup
    query = JrcServiceDesk::CatalogQuery.new(user_context: context, resource: @args.fetch('resource'), parameters: @args.except('resource'))
    result = query.collection
    resources = [['JrcNico::ServiceDeskLookup', @access.account.id]]
    resources << ['JrcServiceDesk::Unit', query.unit_id] if query.unit_id
    resources << ['JrcNico::ServiceDeskRequesters', @access.account.id] if query.resource == 'requesters'
    resources << ['JrcNico::ServiceDeskTeams', @access.account.id] if query.resource == 'teams'
    result[:items].each do |record|
      resources << [record.class.name, record.id] if JrcNico::DomainAccess::RESOURCE_TYPES.include?(record.class.name) || record.is_a?(Contact)
      resources << ['JrcNico::ServiceDeskAssignable', record.id] if query.resource == 'assignees'
    end
    items = result[:items].map { |record| presenter.catalog(record, resource: query.resource, unit_id: query.unit_id) }
    resources += items.filter_map { |row| ['Team', row[:team][:id].to_i] if row[:team] }
    { items: items, meta: result[:meta].except(:total), resources: resources.uniq }
  end

  def create_service_ticket
    conversation = @access.conversation(@args['conversation_id']) if @args['conversation_id']
    ticket = JrcServiceDesk::CreateTicketWorkflowService.new(user_context: context).call(
      unit_id: @args.fetch('unit_id'), attributes: @args.slice(*JrcServiceDesk::CreateTicketService::FIELDS),
      idempotency_key: request_key, conversation_id: conversation&.id, service_id: @args['service_id'])
    ticket_result(ticket, message: 'Chamado criado ou recuperado pelo Service Desk R2.')
  end

  def change_service_ticket(name)
    service = { 'update_service_ticket' => JrcServiceDesk::UpdateTicketService,
                'assign_service_ticket' => JrcServiceDesk::AssignTicketService,
                'transfer_service_ticket' => JrcServiceDesk::TransferTicketService }.fetch(name)
    options = { ticket_id: @args.fetch('ticket_id'), attributes: @args.slice(*service::FIELDS),
                expected_lock_version: @args.fetch('expected_lock_version') }
    options[:execution_command] = @command if name == 'update_service_ticket'
    ticket = service.new(user_context: context).call(**options)
    # Assignment can legitimately remove the actor's read scope. Match the native
    # endpoint's acknowledgement instead of requiring a new post-write read.
    receipt(ticket, { id: ticket.id, applied: true }, message: 'Chamado atualizado pelo Service Desk R2.', route: 'jrc_service_desk_tickets')
  end

  def add_service_ticket_note
    note = JrcServiceDesk::AddNoteService.new(user_context: context).call(ticket_id: @args.fetch('ticket_id'),
      attributes: @args.slice('body'), idempotency_key: request_key)
    receipt(note, { id: note.id, ticket_id: note.ticket_id }, message: 'Nota interna registrada no chamado.')
  end

  def read_service_ticket_lifecycle
    ticket = @domain.ticket(@args.fetch('ticket_id'))
    result = JrcServiceDesk::LifecycleReadService.new(user_context: context, ticket: ticket).call(page: @args.fetch('page', 1))
    result[:meta] = result[:meta].except(:total)
    resources = [['JrcNico::ServiceTicketLifecycle', ticket.id]]
    Array(result[:history]).each do |row|
      resources << ['JrcServiceDesk::LifecycleTransition', row[:id].to_i]
      if JrcServiceDesk::HistoryProjection.protected_input?(row[:payload])
        resources << ['JrcNico::ServiceTicketNotes', ticket.id]
        resources += Array(row[:payload]['evidence_note_ids']).map { |id| ['JrcServiceDesk::TicketNote', id] }
      end
    end
    receipt(ticket, { id: ticket.id }, message: nil).merge(details: result, resources: resources.uniq)
  end

  def transition_service_ticket
    transition = JrcServiceDesk::LifecycleTransitionService.new(user_context: context).call(ticket_id: @args.fetch('ticket_id'),
      attributes: @args.slice(*JrcServiceDesk::LifecycleTransitionService::FIELDS), idempotency_key: request_key,
      execution_command: @command)
    result = ticket_result(@domain.ticket(transition.ticket_id), message: 'Regra de ciclo de vida aplicada pelo Service Desk R2.')
    result[:resources] << ['JrcServiceDesk::LifecycleTransition', transition.id]
    result
  end

  def link_service_ticket_conversation
    conversation = @access.conversation(@args.fetch('conversation_id'))
    JrcServiceDesk::LinkConversationService.new(user_context: context).call(ticket_id: @args.fetch('ticket_id'), conversation_id: conversation.id)
    ticket_result(@domain.ticket(@args.fetch('ticket_id')), message: 'Conversa vinculada pelo Service Desk R2.').merge(conversation_id: conversation.display_id)
  end

  def page(scope)
    scope.offset((@args.fetch('page', 1) - 1) * 20).limit(20)
  end

  def collection(items)
    { items: items, resources: items.flat_map { |item| Array(item[:resources]) + [[item[:resource_type], item.dig(:record, 'id')]] }.uniq }
  end

  def list_projects
    scope = JrcOperations::Access.projects(@access.membership)
    scope = scope.where(status: @args['status']) if @args['status']
    scope = scope.where('name ILIKE ?', "%#{JrcProjects::Project.sanitize_sql_like(@args['query'])}%") if @args['query']
    collection(page(scope.order(updated_at: :desc, id: :desc)).map { |project| project_result(project) })
  end

  def project_result(project, details: false, message: nil)
    # Detail panels also contain budget and audit data with independent permissions.
    # This connector advertises project basics and board columns only.
    data = JrcProjects::ProjectSerializer.one(project, account_user: @access.membership)
    resources = [[project.class.name, project.id]]
    if project.contact_id
      begin
        @access.contact(project.contact_id)
        resources << ['Contact', project.contact_id]
      rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
        data.except!('contact', 'contact_id')
      end
    end
    if JrcProjects::Authorization.allowed?(account_user: @access.membership, capability: 'projects.task.view', project: project)
      resources << ['JrcNico::ProjectTasks', project.id]
      if details
        data['columns'] = project.board_columns.where(account_id: @access.account.id).order(:board_id, :position, :id).limit(50)
          .as_json(only: %i[id board_id name status_key position wip_limit])
      end
    else
      data.except!('tasks_total', 'tasks_completed', 'progress')
    end
    receipt(project, data, message: message, route: 'jrc_projects_list').merge(resources: resources)
  end

  def task_result(task, message: nil)
    receipt(task, task.attributes.slice('id', 'project_id', 'parent_id', 'title', 'description', 'status', 'priority',
      'board_column_id', 'assignee_id', 'starts_on', 'due_on', 'estimated_minutes', 'lock_version'), message: message, route: 'jrc_projects_list')
  end

  def list_project_tasks
    project = @domain.project(@args.fetch('project_id'), capability: 'projects.task.view')
    scope = project.tasks.where(account_id: @access.account.id)
    scope = scope.where(status: @args['status']) if @args['status']
    result = collection(page(scope.order(:position, :id)).map do |task|
      @domain.authorize_project!(project, 'projects.task.view', task)
      task_result(task)
    end)
    result[:resources] << ['JrcNico::ProjectTasks', project.id]
    result
  end

  def create_project
    template = JrcProjects::ProjectTemplate.where(account_id: @access.account.id, active: true).find(@args['template_id']) if @args['template_id']
    origin = @args.slice('deal_id', 'ticket_id')
    origin['conversation_display_id'] = @args['conversation_id'] if @args['conversation_id']
    project = JrcProjects::Projects::Create.call(account: @access.account, actor: @access.user,
      attributes: @args.slice('name', 'key', 'description', 'visibility', 'contact_id', 'starts_on', 'due_on', 'priority'),
      template: template, origin: origin, idempotency_key: request_key, correlation_id: request_key)
    project_result(project, message: 'Projeto criado ou recuperado pelo módulo de Projetos.')
  end

  def update_project
    project = JrcProjects::Projects::Update.call(account: @access.account, actor: @access.user,
      project: @domain.project(@args.fetch('project_id')), attributes: @args.except('project_id'), correlation_id: request_key)
    project_result(project, message: 'Projeto atualizado pelo módulo de Projetos.')
  end

  def create_project_task
    key = request_key
    @access.account.with_lock do
      ticket = @domain.ticket(@args['ticket_id']) if @args['ticket_id']
      project = @domain.project(@args.fetch('project_id'), capability: 'projects.task.create')
      @domain.authorize_project!(project, 'projects.task.view')
      task = JrcProjects::Tasks::Create.call(account_user: @access.membership, project: project,
                                           attributes: @args.except('project_id', 'ticket_id'), correlation_id: key)
      resources = [[project.class.name, project.id], ['JrcNico::ProjectTasks', project.id], [task.class.name, task.id]]
      if ticket
        link = JrcOperations::Linker.new(account_user: @access.membership, correlation_id: key).create!(
          attributes: { project_id: project.id, task_id: task.id, ticket_id: ticket.id }
        )
        resources += [[ticket.class.name, ticket.id], [link.class.name, link.id]]
      end
      task_result(task, message: 'Tarefa criada pelo módulo de Projetos.').merge(resources: resources)
    end
  end

  def move_project_task
    task = @domain.task(@args.fetch('project_id'), @args.fetch('task_id'), capability: 'projects.task.move')
    column = task.project.board_columns.where(account_id: @access.account.id).find(@args.fetch('column_id'))
    JrcProjects::Tasks::Move.call(task: task, actor: @access.user, column: column, lock_version: @args.fetch('lock_version'),
      before_task_id: @args['before_task_id'], correlation_id: request_key)
    task_result(task.reload, message: 'Tarefa movimentada pelo módulo de Projetos.')
  end

  def read_operations_agenda
    result = JrcOperations::Agenda.new(account_user: @access.membership, filters: @args).call
    raise ArgumentError, 'Mais de 50 compromissos: reduza o periodo ou filtre o responsavel.' if result[:data].length > 50

    # Native counts also include entries outside the selected view. Keep the saved
    # response restricted to records represented in its resource manifest.
    result[:meta] = result[:meta].except(:users, :counts).merge(returned: result[:data].length)
    types = { 'project_task' => 'JrcProjects::Task', 'crm_activity' => 'JrcCrm::Activity', 'crm_follow_up' => 'JrcCrm::FollowUp' }
    result.merge(resources: result[:data].map { |row| [types.fetch(row[:kind]), row[:id].split(':').last.to_i] })
  end

  def operation_source
    @args.except('conversation_id').merge(@args['conversation_id'] ? { 'conversation_display_id' => @args['conversation_id'] } : {})
  end

  def read_operation_links
    result = JrcOperations::Related.new(account_user: @access.membership, source: operation_source).call
    result.except!(:tickets_total, :projects_total)
    resources = operation_source_resources + Array(result[:tickets]).map { |row| ['JrcServiceDesk::Ticket', row['id']] } +
                Array(result[:projects]).map { |row| ['JrcProjects::Project', row['id']] } +
                Array(result[:deals]).map { |row| ['JrcCrm::Deal', row['id']] } +
                Array(result[:relations]).map { |row| ['JrcOperations::Link', row[:id]] }
    if @args['ticket_id']
      ticket = @domain.ticket(@args['ticket_id'])
      if @access.policy(ticket).view_conversations?
        if result[:conversations].any? || result[:relations].any? { |row| row[:conversation] }
          resources << ['JrcNico::ServiceTicketConversations', ticket.id]
        end
      else
        result[:conversations] = []
        result[:relations].each { |row| row.delete(:conversation) }
      end
    end
    ticket_rows = Array(result[:tickets]) + Array(result[:relations]).filter_map { |row| row[:ticket] }
    ticket_rows.each do |row|
      begin
        ticket = @domain.ticket(row.fetch('id'))
        Pundit.authorize(context, ticket, :view_customer?)
        contact = @access.contact(row.fetch('requester_id'))
        resources += [['JrcNico::ServiceTicketCustomer', ticket.id], ['Contact', contact.id]]
      rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
        row.delete('requester_id')
      end
    end
    contact_rows = Array(result[:deals]) + Array(result[:relations]) + Array(result[:relations]).filter_map { |row| row[:deal] }
    contact_rows.each do |row|
      key = row.key?(:contact) ? :contact : 'contact'
      next unless row[key]

      if row[:ticket] && !row[:ticket].key?('requester_id')
        row.delete(key)
        next
      end

      begin
        contact = @access.contact(row[key].fetch('id'))
        resources << ['Contact', contact.id]
      rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
        row.delete(key)
      end
    end
    # Related's deal scope authorizes the deal itself. Organization/company detail
    # reads are not part of this connector's contract.
    (Array(result[:deals]) + Array(result[:relations]).filter_map { |row| row[:deal] }).each { |row| row.except!('organization', 'company') }
    conversations = Array(result[:conversations]).map { |row| row[:id] }
    conversations << @args['conversation_id'] if @args['conversation_id']
    result.merge(resources: resources.uniq, conversation_ids: conversations.uniq)
  end

  def operation_source_resources
    { 'project_id' => 'JrcProjects::Project', 'ticket_id' => 'JrcServiceDesk::Ticket',
      'deal_id' => 'JrcCrm::Deal', 'contact_id' => 'Contact' }.filter_map do |key, type|
      [type, @args[key]] if @args[key]
    end
  end

  def link_project_record
    link = JrcOperations::Linker.new(account_user: @access.membership, correlation_id: request_key).create!(attributes: operation_source)
    receipt(link, { id: link.id, project_id: link.project_id }, message: 'Vínculo registrado pelo módulo de Projetos.')
  end

  def unlink_project_record
    JrcOperations::Linker.new(account_user: @access.membership, correlation_id: request_key)
      .destroy!(id: @args.fetch('link_id'), source: @args.slice('project_id', 'ticket_id', 'deal_id'))
    { message: 'Vinculo removido pelo modulo de Projetos.', resources: operation_source_resources }
  end

  def crm_list(kind)
    model, owner, fields = CRM_READS.fetch(kind)
    scope = @access.crm_scope(model, owner: owner)
    scope = scope.where(status: @args['status']) if @args['status']
    page(scope.order(updated_at: :desc, id: :desc)).map { |record| receipt(record, record.attributes.slice(*fields)) }
  end

  def crm_read(kind)
    _model, _owner, fields = CRM_READS.fetch(kind)
    record = JrcNico::DomainAccess.authorize_resource!(@access, CRM_READS.fetch(kind).first.name, @args.fetch("#{kind}_id"))
    receipt(record, record.attributes.slice(*fields))
  end

  def convert_proposal_to_order
    proposal = @access.crm_scope(JrcCrm::Proposal).find(@args.fetch('proposal_id'))
    raise Pundit::NotAuthorizedError unless @access.policy(proposal).update?

    order = JrcCrm::ProposalToOrderService.new(proposal: proposal, actor: @access.user).call
    receipt(order, order.attributes.slice(*CRM_READS['sales_order'][2]), message: 'Pedido criado ou recuperado a partir da proposta aceita.', route: 'crm_orders')
  end

  def list_sales_goals
    raise Pundit::NotAuthorizedError unless @access.crm? && @access.membership.administrator?

    scope = JrcCrm::SalesGoal.where(account_id: @access.account.id)
    scope = scope.where(status: @args['status']) if @args['status']
    page(scope.order(period_start: :desc, id: :desc)).map do |goal|
      receipt(goal, goal.attributes.slice('id', 'name', 'status', 'metric', 'period_start', 'period_end', 'target_cents', 'target_quantity')).merge(
        progress: JrcCrm::GoalProgressService.new(goal: goal).call)
    end
  end

  def list_commission_programs
    raise Pundit::NotAuthorizedError unless @access.crm? && @access.membership.administrator?

    page(JrcCrm::CommissionProgram.where(account_id: @access.account.id).order(id: :desc)).map do |program|
      receipt(program, program.attributes.slice('id', 'name', 'release_condition', 'starts_on', 'ends_on', 'active'))
    end
  end
end
