# frozen_string_literal: true

class JrcServiceDesk::CockpitProjection
  def initialize(ticket:, context:)
    @ticket = ticket
    @context = JrcServiceDesk::OperationalContext.new(context)
    @policy = JrcServiceDesk::TicketPolicy.new(@context.to_h, ticket)
    @presenter = JrcServiceDesk::Presenter.new(user_context: @context.to_h)
    @operations = JrcServiceDesk::OperationsPresenter.new(context: @context)
  end

  def call
    { notes: related(JrcServiceDesk::TicketNote, 'notes', @policy.view_notes?),
      events: related(JrcServiceDesk::TicketEvent, 'events', @policy.view_history?),
      tasks: operations(JrcServiceDesk::TicketTask, 'tasks', @context.capability?(:tasks_view)),
      approvals: operations(JrcServiceDesk::TicketApproval, 'approvals', @context.capability?(:approvals_view)),
      incident: incident, conversations: conversations, ola: ola,
      audience_values: JrcServiceDesk::InteractionVisibility::VALUES, approvers: approvers }
  end

  private

  def rows(model)
    Pundit.policy_scope!(@context.to_h, model).where(account_id: @ticket.account_id, unit_id: @ticket.unit_id, ticket_id: @ticket.id)
  end

  def related(model, kind, allowed)
    allowed ? rows(model).order(:created_at, :id).map { |row| @presenter.related(row, kind) } : []
  end

  def operations(model, kind, allowed)
    allowed ? rows(model).order(:id).map { |row| @operations.call(kind, row) } : []
  end

  def incident
    record = @ticket.incident
    @operations.call('incidents', record) if record && JrcServiceDesk::IncidentPolicy.new(@context.to_h, record).show?
  end

  def ola
    @policy.view_sla? ? @ticket.ola_clocks.order(:id).map { |row| @operations.call('ola', row) } : []
  end

  def conversations
    return [] unless @policy.view_conversations?

    @ticket.ticket_conversations.includes(conversation: :inbox).filter_map do |link|
      next unless JrcServiceDesk::TicketConversationPolicy.new(@context.to_h, link).show?

      { id: link.conversation_id.to_s, display_id: link.conversation.display_id.to_s,
        channel: JrcServiceDesk::NotificationEngine.channel(link.conversation.inbox),
        customer_recipient: link.conversation.contact_id == @ticket.requester_id }
    end
  end

  def approvers
    return [] unless @context.capability?(:approvals_request) && @context.capability?(:lookups_view)

    query = JrcServiceDesk::CatalogQuery.new(user_context: @context.to_h, resource: 'assignees',
                                             parameters: { unit_id: @ticket.unit_id.to_s, page: 1, per_page: 100 })
    query.collection[:items].filter_map { |membership| approver(membership.account_user) }
  end

  def approver(member)
    target = JrcServiceDesk::OperationalContext.new(account: @context.account, user: member.user, account_user: member)
    { id: member.id.to_s, name: member.user.name.to_s } if target.capability?(:approvals_decide)
  end
end
