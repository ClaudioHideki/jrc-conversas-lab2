# frozen_string_literal: true

# Explicit human generalization of a currently visible closed native case; private draft only.
class JrcNico::Helpdesk::GroupNativeKnowledge
  TOOL = 'prepare_closed_case_knowledge'.freeze

  def initialize(context:, event:, group_key:, input:)
    @context, @event, @group, @input = context, event, group_key, input
  end

  def evidence!(value)
    return unless @input

    arguments = arguments_for
    value[:resources].concat([['JrcServiceDesk::Ticket', ticket.id], ['JrcServiceDesk::LifecycleTransition', transition.id],
      ['JrcNico::ServiceTicketCustomer', ticket.id], ['Contact', ticket.requester_id]])
    value[:evidence] << { kind: 'human_reviewed_closed_case_draft', id: transition.id, ticket_id: ticket.id,
      source_digest: arguments.fetch('source_digest'), customer_visible: false, approved: false }
  end

  def candidate
    { tool: TOOL, arguments: arguments_for } if @input
  end

  def source
    { 'event_id' => @event.id, 'ticket_id' => ticket.id, 'unit_id' => ticket.unit_id, 'closed_transition_id' => transition.id,
      'customer_id' => ticket.requester_id, 'company_id' => ticket.company_id, 'closed_at' => transition.occurred_at.iso8601(6),
      'transition_digest' => JrcNico::Helpdesk::Definition.digest(transition.payload) }
  end

  def transition
    @transition ||= JrcNico::DomainAccess.authorize_resource!(@context.access, 'JrcServiceDesk::LifecycleTransition',
      @input.fetch('closed_transition_id'))
  end

  def ticket
    @ticket ||= authorized_ticket
  end

  private

  def arguments_for
    raise Pundit::NotAuthorizedError unless @group == 'E'

    @context.administrator!
    id = @input['closed_transition_id']
    raise ArgumentError, 'Explicit closed transition identifier required' unless id.is_a?(Integer) && id.positive?

    %w[title body].each do |key|
      limit = key == 'title' ? 200 : 4000
      value = @input[key]
      raise ArgumentError, 'Explicit human-reviewed generalized text required' unless value.is_a?(String) && value.strip.size.between?(1, limit)
    end
    unless @input['generalization_reviewed'] == true
      raise ArgumentError, 'Explicit human generalization review required'
    end
    arguments = @input.merge('event_id' => @event.id, 'source_digest' => JrcNico::Helpdesk::Definition.digest(source))
    JrcNico::ToolCatalog.new(@context.access).validate!(TOOL, arguments)
    arguments
  end

  def authorized_ticket
    row = @context.ticket(transition.ticket_id)
    origin = @context.ticket(@event.ticket_id)
    same_customer = origin.company_id ? row.company_id == origin.company_id : row.requester_id == origin.requester_id && row.company_id.nil?
    valid = row.unit_id == origin.unit_id && same_customer && row.status.phase == 'closed' && transition.action == 'close' &&
      row.lifecycle_transitions.where(action: 'close').maximum(:id) == transition.id
    raise Pundit::NotAuthorizedError unless valid

    Pundit.authorize(@context.native.to_h, row, :view_history?)
    Pundit.authorize(@context.native.to_h, row, :view_customer?)
    contact = @context.access.contact(row.requester_id)
    raise Pundit::NotAuthorizedError unless contact.company_id == row.company_id

    row
  end
end
