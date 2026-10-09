class JrcNico::Helpdesk::EventProcessor
  def initialize(event)
    @event = event
  end

  def call
    @event.with_lock do
      next @event unless @event.state == 'detected'

      context = JrcNico::Helpdesk::Context.new(@event.actor)
      context.event(@event.id)
      ticket = context.ticket(@event.ticket_id)
      unless @event.policy_version.eligible?(ticket, context.member)
        @event.update!(state: 'blocked', reason: 'policy_disabled_or_scope_revoked')
        next @event
      end
      mark_profile!(context, ticket)
      @event.update!(state: 'prepared', reason: 'approval_required', result: preview(context))
    end
    notify!
    @event
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    @event.update!(state: 'blocked', reason: 'permission_revoked')
    @event
  end

  private

  def mark_profile!(context, ticket)
    key = { 'R01' => 'recurrent', 'R10' => 'complaint', 'R11' => 'legal_risk' }[@event.rule_key]
    return unless key

    Pundit.authorize(context.native.to_h, ticket, :update?)
    profile = JrcNico::Helpdesk::TicketProfile.find_or_initialize_by(account: context.account, ticket: ticket)
    profile.assign_attributes(unit: ticket.unit, company_id: ticket.company_id)
    profile[key] = true
    profile.save!
  end

  def preview(context)
    value = { 'tools' => JrcNico::Helpdesk::ActionPreview::RULE_TOOLS.fetch(@event.rule_key), 'automatic_mutation' => false }
    arguments = JrcNico::Helpdesk::ActionPreview.new(context: context, event: @event).priority_arguments if %w[R01 R11 R12].include?(@event.rule_key)
    value['priority_arguments'] = arguments if arguments
    value['priority_dependency'] = 'explicit_priority_order_required_or_exhausted' if %w[R01 R11 R12].include?(@event.rule_key) && !arguments
    value['survey_decision_id'] = @event.evidence['survey_decision_id'] if @event.rule_key == 'R15'
    value['human_review'] = true if %w[R10 R11 R14 R16].include?(@event.rule_key)
    value
  end

  def notify!
    return unless @event.state == 'prepared'

    rule = @event.policy_version.definition.fetch('rules').fetch(@event.rule_key)
    rule.fetch('recipients').each do |id|
      member = @event.account.account_users.find_by(id: id)
      next unless member

      rule.fetch('channels').each { |channel| JrcNico::Helpdesk::Delivery.new(source: @event, recipient: member, channel: channel).call }
    end
  end
end
