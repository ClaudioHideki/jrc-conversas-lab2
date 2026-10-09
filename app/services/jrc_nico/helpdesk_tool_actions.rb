class JrcNico::HelpdeskToolActions
  def initialize(access, command: nil)
    @access = access.authorize!
    @domain = JrcNico::DomainAccess.new(@access)
    @command = command
  end

  def call(name, arguments)
    JrcNico::ToolCatalog.new(@access).validate!(name, arguments)
    case name
    when 'prepare_incident_campaign', 'prepare_closed_case_knowledge'
      JrcNico::Helpdesk::GroupDraftActions.new(@access, @command).call
    when 'read_service_ticket_tasks' then list(arguments, JrcServiceDesk::TicketTask, 'tasks')
    when 'read_service_ticket_approvals' then list(arguments, JrcServiceDesk::TicketApproval, 'approvals')
    when 'read_service_incident'
      row = JrcNico::DomainAccess.authorize_resource!(@access, 'JrcServiceDesk::Incident', arguments.fetch('incident_id'))
      incident_result(row)
    when 'create_service_ticket_task' then create_task(arguments)
    when 'create_service_incident'
      row = JrcServiceDesk::CreateIncidentService.new(user_context: @domain.context).call(
        unit_id: arguments.fetch('unit_id'), attributes: arguments.except('unit_id'), idempotency_key: request_key
      )
      incident_result(row)
    else raise ArgumentError, 'HelpDesk tool is unavailable'
    end
  end

  private

  def create_task(arguments)
    @domain.ticket(arguments.fetch('ticket_id'))
    row = JrcServiceDesk::CreateTaskService.new(user_context: @domain.context).call(
      ticket_id: arguments.fetch('ticket_id'), attributes: arguments.except('ticket_id').merge('visibility' => 'internal'),
      idempotency_key: request_key
    )
    result(row, %w[id ticket_id title status priority due_at checklist], 'Tarefa interna registrada')
  end

  def request_key
    unless @command&.persisted? && @command.session.account_id == @access.account.id && @command.session.user_id == @access.user.id
      raise ArgumentError, 'Prepare a native NICO command first'
    end

    "nico_#{@command.id}_#{@command.request_id}"
  end

  def list(arguments, model, key)
    @domain.ticket(arguments.fetch('ticket_id'))
    page = arguments.fetch('page', 1)
    scope = Pundit.policy_scope!(@domain.context, model).where(ticket_id: arguments.fetch('ticket_id')).order(id: :desc)
    rows = scope.limit(20).offset((page - 1) * 20).select { |row| Pundit.policy!(@domain.context, row).show? }
    { items: rows.map { |row| result(row, %w[id ticket_id title status due_at], 'Registro autorizado') },
      page: page, route_name: 'jrc_service_desk', resources: rows.map { |row| [model.name, row.id] }, collection: key }
  end

  def incident_result(row)
    tickets = row.tickets.order(:id).to_a
    tickets.each { |ticket| @domain.ticket(ticket.id) }
    value = result(row, %w[id unit_id title severity status primary_ticket_id started_at], 'Incidente nativo registrado')
    value.merge(ticket_ids: tickets.map(&:id), resources: value.fetch(:resources) + tickets.map { |ticket| ['JrcServiceDesk::Ticket', ticket.id] })
  end

  def result(row, fields, message)
    JrcNico::DomainAccess.authorize_resource!(@access, row.class.name, row.id)
    { resource_type: row.class.name, id: row.id, record: row.attributes.slice(*fields), message: message,
      route_name: 'jrc_service_desk', resources: [[row.class.name, row.id]] }
  end
end
