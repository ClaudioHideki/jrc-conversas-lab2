# A finite proposal into the existing OperatorSession. No HTTP/tool dispatch is generated from customer content.
class JrcNico::Helpdesk::ActionPreview
  RULE_TOOLS = {
    'R01' => %w[update_service_ticket add_service_ticket_note], 'R02' => %w[create_project create_project_task add_service_ticket_note],
    'R03' => %w[add_service_ticket_note], 'R04' => %w[create_service_incident add_service_ticket_note], 'R05' => %w[add_service_ticket_note],
    'R06' => %w[add_service_ticket_note], 'R07' => %w[create_service_ticket_task create_project create_project_task add_service_ticket_note],
    'R08' => %w[add_service_ticket_note],
    'R09' => %w[add_service_ticket_note], 'R10' => %w[add_service_ticket_note], 'R11' => %w[update_service_ticket add_service_ticket_note],
    'R12' => %w[update_service_ticket add_service_ticket_note], 'R13' => %w[add_service_ticket_note],
    'R14' => %w[transition_service_ticket], 'R15' => [], 'R16' => %w[assign_service_ticket add_service_ticket_note]
  }.freeze

  def initialize(context:, event:, group_scope: nil)
    @context = context
    @event = event
    @ticket = context.ticket(event.ticket_id)
    @group_scope = group_scope
  end

  def priority_arguments
    return critical_priority_arguments if @event.rule_key == 'R12'

    order = @event.policy_version.definition.fetch('priority_order').fetch(@ticket.unit_id.to_s, [])
    index = order.index(@ticket.priority_id)
    return unless index && index < order.size - 1

    target = @event.rule_key == 'R11' ? order.last : order[index + 1]
    { 'ticket_id' => @ticket.id, 'expected_lock_version' => @ticket.lock_version, 'priority_id' => target }
  end

  def validate!(tool, arguments)
    if @group_scope
      JrcNico::Helpdesk::GroupActionPreview.new(context: @context, event: @event,
        group_key: @group_scope.fetch('group_key'), input: @group_scope.fetch('input'))
        .validate_scope!(@group_scope, tool: tool, arguments: arguments)
      return arguments
    end
    raise Pundit::NotAuthorizedError unless RULE_TOOLS.fetch(@event.rule_key).include?(tool)

    JrcNico::ToolCatalog.new(@context.access).validate!(tool, arguments)
    validate_scope!(tool, arguments)
    validate_priority!(arguments) if tool == 'update_service_ticket'
    validate_transition!(arguments) if tool == 'transition_service_ticket'
    arguments
  end

  private

  def critical_priority_arguments
    target = @event.policy_version.definition.dig('rules', 'R12', 'priority_ids', @ticket.unit_id.to_s)
    return unless target && target != @ticket.priority_id
    return unless JrcServiceDesk::Priority.exists?(account: @context.account, unit_id: @ticket.unit_id, id: target, active: true)

    { 'ticket_id' => @ticket.id, 'expected_lock_version' => @ticket.lock_version, 'priority_id' => target }
  end

  def validate_scope!(tool, arguments)
    if tool == 'create_service_incident'
      raise Pundit::NotAuthorizedError unless arguments['unit_id'] == @ticket.unit_id &&
                                              arguments['ticket_ids'].sort == @event.evidence.fetch('ticket_ids').sort

      arguments['ticket_ids'].each { |id| @context.ticket(id) }
    else
      raise Pundit::NotAuthorizedError unless arguments['ticket_id'] == @ticket.id

      validate_project_task_scope!(arguments) if tool == 'create_project_task'
    end
  end

  def validate_project_task_scope!(arguments)
    domain = JrcNico::DomainAccess.new(@context.access)
    project = domain.project(arguments.fetch('project_id'), capability: 'projects.task.create')
    domain.authorize_project!(project, 'projects.task.view')
    unless project.operation_links.where(account_id: @context.account.id, ticket_id: @ticket.id,
                                         ticket_unit_id: @ticket.unit_id).exists?
      raise Pundit::NotAuthorizedError
    end
  end

  def validate_priority!(arguments)
    expected = priority_arguments
    raise ArgumentError, 'Explicit priority ordering is missing or exhausted' unless expected
    raise ArgumentError, 'Priority preview no longer matches' unless arguments == expected
  end

  def validate_transition!(arguments)
    validate_negative_evidence!
    unless @ticket.lifecycle_policy_version_id == arguments['expected_policy_version_id']
      raise ArgumentError,
            'A pinned lifecycle version is required'
    end

    rule = JrcServiceDesk::LifecycleRules.new(@ticket.lifecycle_policy_version.definition).rule(arguments.fetch('rule_key'))
    raise ArgumentError, 'Only a configured reopen action is allowed' unless rule.fetch('action') == 'reopen'
  end

  def validate_negative_evidence!
    profile = JrcNico::Helpdesk::TicketProfile.find_by(account: @context.account, ticket: @ticket)
    fields = JrcNico::Helpdesk::CycleEvidence::FIELDS
    current = profile&.evidence&.slice(*fields)
    raise ArgumentError, 'The negative-return attestation changed' unless current == @event.evidence.slice(*fields)
    raise ArgumentError, 'A review for the current ticket cycle is required' unless current_cycle? &&
                                                                                    JrcNico::Helpdesk::CycleEvidence.valid_negative?(
                                                                                      ticket: @ticket, profile: profile,
                                                                                      cycle_key: @event.evidence['cycle_key'],
                                                                                      context: @context, now: Time.current
                                                                                    )
  end

  def current_cycle?
    @event.evidence['same_ticket_id'] == @ticket.id && @event.evidence['cycle_key'] == JrcNico::Helpdesk::CycleEvidence.key(@ticket)
  end
end
