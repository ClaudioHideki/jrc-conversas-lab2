# frozen_string_literal: true

# Only actual native customer reply evidence can complete first response. Assignment,
# internal note, silent public publication and elapsed wall time are not evidence.
class JrcServiceDesk::NativeResponseRecorder
  def initialize(message, evidence: nil)
    @message = message
    @evidence = evidence
  end

  def self.evidence(message)
    { 'account_id' => message.account_id, 'conversation_id' => message.conversation_id,
      'source_id' => message.source_id, 'status' => message.status, 'observed_at' => message.updated_at.iso8601(6) }
  end

  def call
    return unless delivered_public_reply?

    account = @message.account
    return unless account.feature_enabled?('jrc_service_desk')

    delivery = delivery(account)
    member = execution_member(account, delivery)
    return unless member

    achieved = accepted_at(delivery)
    return unless achieved

    context = JrcServiceDesk::OperationalContext.new(account: account, user: member.user, account_user: member)
    visible_tickets(context).find_each { |ticket| record_ticket(ticket, context, achieved) }
  rescue JrcServiceDesk::LifecycleDependencyError, Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    # Missing explicit SLA/calendar remains pending; no default budget is fabricated.
    nil
  end

  private

  def accepted_at(delivery)
    delivery&.sent_at || observed_at
  end

  def delivered_public_reply?
    @message.outgoing? && !@message.private? && @message.content.present? &&
      (@message.source_id.present? || %w[delivered read].include?(@message.status))
  end

  def delivery(account)
    id = @message.content_attributes['service_desk_delivery_id']
    return unless id

    JrcServiceDesk::NotificationDelivery.find_by(account_id: account.id, message_id: @message.id,
                                                 conversation_id: @message.conversation_id, id: id)
  end

  def execution_member(account, delivery)
    if delivery
      return unless %w[sent delivered read].include?(delivery.state)

      delivery.execution_membership.account_user
    elsif @message.sender.is_a?(User)
      AccountUser.find_by(account_id: account.id, user_id: @message.sender.id)
    end
  end

  def visible_tickets(context)
    links = JrcServiceDesk::TicketConversation.where(account_id: context.account.id, conversation_id: @message.conversation_id).pluck(:ticket_id)
    JrcServiceDesk::TicketPolicy::Scope.new(context.to_h, JrcServiceDesk::Ticket).resolve
                                       .where(id: links, requester_id: @message.conversation.contact_id)
  end

  def record_ticket(ticket, context, achieved)
    command = JrcServiceDesk::BaseService.new(user_context: context.to_h)
    command.send(:with_ticket, ticket.id, :show?) do |locked|
      policy = JrcServiceDesk::LifecycleSelector.new(locked).applicable
      next unless policy && policy.definition.dig('sla', 'mode') == 'calendar_snapshot'

      cycle = cycle(locked, policy, context.account)
      clock = cycle.sla_clocks.lock.find_by(kind: 'first_response')
      next unless clock&.state == 'running'

      record_clock(command, locked, cycle, clock, achieved)
    end
  end

  def cycle(ticket, policy, account)
    existing = ticket.sla_cycles.order(number: :desc).first
    return existing if existing

    ticket.update!(lifecycle_policy_version: policy) unless ticket.lifecycle_policy_version_id
    snapshot = ticket.latest_sla_snapshot
    calendar = JrcServiceDesk::LifecycleClocks.verify_snapshot!(snapshot, clock_kinds: policy.rules.clock_kinds)
    cycle = ticket.sla_cycles.create!(account: account, unit: ticket.unit, lifecycle_policy_version: policy,
                                      sla_snapshot: snapshot, number: 1, started_at: ticket.opened_at)
    snapshot.policy_conditions['clock_budgets_seconds'].each do |kind, budget|
      create_clock(cycle, ticket, kind, budget, calendar)
    end
    cycle
  end

  def create_clock(cycle, ticket, kind, budget, calendar)
    cycle.sla_clocks.create!(account: cycle.account, unit: ticket.unit, ticket: ticket, kind: kind, budget_seconds: budget,
                             state: 'running', elapsed_seconds: 0, anchor_at: ticket.opened_at,
                             due_at: calendar.advance(ticket.opened_at, budget), calculator_version: JrcServiceDesk::SnapshotCalendar::VERSION)
  end

  def record_clock(command, ticket, cycle, clock, achieved)
    calendar = JrcServiceDesk::LifecycleClocks.verify_snapshot!(cycle.sla_snapshot)
    return if achieved < cycle.started_at || achieved < clock.anchor_at

    clock.update!(state: 'completed', elapsed_seconds: clock.elapsed_seconds + calendar.elapsed(clock.anchor_at, achieved),
                  anchor_at: achieved, achieved_at: achieved)
    command.send(:append_event!, ticket, 'first_response_recorded',
                 'message_id' => @message.id, 'conversation_id' => @message.conversation_id, 'clock_id' => clock.id,
                 'cycle_id' => cycle.id, 'achieved_at' => achieved.iso8601(6), 'snapshot_id' => cycle.sla_snapshot_id)
  end

  def observed_at
    return unless bound_evidence? && accepted_evidence? && @evidence['source_id'] == @message.source_id

    observed = Time.iso8601(@evidence.fetch('observed_at'))
    observed if observed.between?(@message.created_at, @message.updated_at)
  rescue ArgumentError, KeyError
    nil
  end

  def bound_evidence?
    @evidence.is_a?(Hash) && @evidence['account_id'] == @message.account_id && @evidence['conversation_id'] == @message.conversation_id
  end

  def accepted_evidence?
    @evidence['source_id'].present? || %w[delivered read].include?(@evidence['status'])
  end
end
