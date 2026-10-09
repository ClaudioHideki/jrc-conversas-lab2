# frozen_string_literal: true

# Every candidate is a native tool plus exact arguments; there is no arbitrary dispatch.
class JrcNico::Helpdesk::GroupActions
  def initialize(context:, event:, group_key:, input:, state:)
    @context = context
    @event = event
    @ticket = context.ticket(event.ticket_id)
    @group = group_key
    @input = input
    @sources = state.fetch(:sources)
    @enabled = state.fetch(:enabled)
    @attempts = state.fetch(:attempts)
    @policy = JrcServiceDesk::TicketPolicy.new(context.native.to_h, @ticket)
  end

  def call
    actions = []
    actions << note_candidate if @input['summary'].present?
    actions << handoff_candidate if @input['handoff'].present?
    actions << classification_candidate if @group == 'D1' && @input['classification'].present?
    native = JrcNico::Helpdesk::GroupNativeActions.new(context: @context, event: @event, group_key: @group, input: @input)
    native.candidates.each { |row| actions << candidate(row[:tool], row[:arguments], permission: true, missing: row[:blocked_reason]) }
    actions.compact
  end

  private

  def candidate(tool, arguments, permission:, missing: nil)
    JrcNico::ToolCatalog.new(@context.access).validate!(tool, arguments)
    allowed = @enabled && permission && missing.nil?
    { tool: tool, arguments: arguments, can_prepare: allowed,
      blocked_reason: allowed ? nil : blocked_reason(missing) }.compact
  end

  def blocked_reason(missing)
    missing || (@enabled ? 'native_permission_required' : 'group_or_policy_disabled')
  end

  def note_candidate
    ids = @sources.fetch(:evidence).map { |row| "#{row.fetch(:kind)}:#{row.fetch(:id)}" }
    body = "NICO HelpDesk #{@group}; source event #{@event.id}; reviewed attempt #{@attempts + 1}\n"
    body += "Evidence: #{ids.join(', ')}\n#{@input.fetch('summary')}"
    missing = 'two_attempts_require_native_handoff' if %w[A2 B1 B2 C1 C2].include?(@group) && @attempts >= 2
    candidate('add_service_ticket_note', { 'ticket_id' => @ticket.id, 'body' => body },
              permission: @policy.add_note?, missing: missing)
  end

  def handoff_candidate
    values = @input.fetch('handoff')
    validate_handoff_targets!(values)
    candidate('assign_service_ticket', values.merge('ticket_id' => @ticket.id, 'expected_lock_version' => @ticket.lock_version),
              permission: @policy.assign?)
  end

  def classification_candidate
    values = @input.fetch('classification')
    validate_classification_targets!(values)
    fields = @sources.fetch(:form_fields)
    answers = @ticket.service_fields.merge(values.fetch('service_fields', {}))
    missing = 'required_catalogue_answers_missing' if @sources.fetch(:required_fields).any?
    JrcServiceDesk::CatalogueAnswers.new(fields).validate!(answers) unless missing
    permission = @policy.update? && (!values.key?('priority_id') || @policy.change_priority?)
    candidate('update_service_ticket', values.merge('ticket_id' => @ticket.id, 'expected_lock_version' => @ticket.lock_version),
              permission: permission, missing: missing)
  end

  def validate_handoff_targets!(values)
    validate_handoff_queue!(values) if values['queue_id']
    if values['team_id']
      team = @context.account.teams.find(values['team_id'])
      Pundit.authorize(@context.native.to_h, team, :show?)
    end
    return unless values['assignee_account_user_id']

    member = @context.account.account_users.find(values['assignee_account_user_id'])
    native = JrcServiceDesk::OperationalContext.new(account: @context.account, user: member.user, account_user: member)
    raise Pundit::NotAuthorizedError unless native.unit_allowed?(@ticket.unit) && native.capability?(:tickets_view)
  end

  def validate_handoff_queue!(values)
    queue = JrcServiceDesk::Queue.where(account: @context.account, unit_id: @ticket.unit_id, active: true).find(values['queue_id'])
    Pundit.authorize(@context.native.to_h, queue, :show?)
    raise Pundit::NotAuthorizedError if values['team_id'] && queue.team_id != values['team_id']
  end

  def validate_classification_targets!(values)
    if values['priority_id']
      priority = JrcServiceDesk::Priority.where(account: @context.account, unit_id: @ticket.unit_id, active: true).find(values['priority_id'])
      Pundit.authorize(@context.native.to_h, priority, :show?)
    end
    return unless values['contract_id']

    Pundit.authorize(@context.native.to_h, @ticket, :view_customer?)
    contract = JrcServiceDesk::CatalogueContracts.new(@context.native).scope.find(values['contract_id'])
    raise Pundit::NotAuthorizedError unless JrcServiceDesk::CatalogueContracts.belongs_to?(contract, @ticket.requester, @ticket.company_id)
  end
end
