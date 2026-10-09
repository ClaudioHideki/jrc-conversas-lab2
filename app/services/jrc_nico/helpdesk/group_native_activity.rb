# frozen_string_literal: true

# An explicit CRM follow-up or meeting; this contract does not send an invitation.
class JrcNico::Helpdesk::GroupNativeActivity
  def self.authorize_result!(context, command)
    row = JrcNico::Helpdesk::GroupNativeActions.authorize_resource!(context, 'JrcCrm::Activity', command.result.fetch('record').fetch('id'))
    ids = command.arguments.slice('lead_id', 'deal_id')
    valid = row.user_id == context.member.user_id && ids.all? { |key, value| row.public_send(key) == value }
    valid &&= row.title == command.arguments['title'] && row.activity_type == command.arguments['activity_type']
    raise Pundit::NotAuthorizedError unless valid
  end

  def initialize(context:, event:, group_key:, input:)
    @context, @event, @group, @input = context, event, group_key, input
    @ticket = context.ticket(event.ticket_id)
  end

  def evidence!(value)
    return unless @input

    arguments = arguments_for
    key = arguments.key?('lead_id') ? 'lead_id' : 'deal_id'
    type = key == 'lead_id' ? 'JrcCrm::Lead' : 'JrcCrm::Deal'
    row = JrcNico::Helpdesk::GroupNativeActions.authorize_resource!(@context, type, arguments.fetch(key))
    authorize_customer!(row)
    value[:resources].concat([[type, row.id], ['JrcNico::ServiceTicketCustomer', @ticket.id], ['Contact', @ticket.requester_id]])
    value[:evidence] << { kind: 'native_customer_crm', id: row.id, resource_type: type, contact_id: row.contact_id, company_id: row.company_id }
  end

  def candidate
    return unless @input

    evidence!({ resources: [], evidence: [] })
    { tool: 'create_activity', arguments: arguments_for }
  end

  private

  def activity_type
    return 'meeting' if @group == 'E' && @event.rule_key == 'R03'
    return 'follow_up' if @group == 'D2' && @event.rule_key == 'R08'

    raise Pundit::NotAuthorizedError
  end

  def arguments_for
    type = activity_type
    ids = %w[lead_id deal_id].select { |key| @input.key?(key) }
    raise ArgumentError, 'Choose exactly one current customer CRM record' unless ids.one?

    validate_date!
    details = @input.fetch('description', '')
    raise ArgumentError, 'Explicit activity description text required' unless details.is_a?(String)

    description = "HelpDesk #{@event.rule_key}; source event #{@event.id}; ticket #{@ticket.id}; Unit #{@ticket.unit_id}\n"
    description += details
    arguments = @input.merge('activity_type' => type, 'description' => description)
    JrcNico::ToolCatalog.new(@context.access).validate!('create_activity', arguments)
    arguments
  end

  def validate_date!
    date = @input.fetch('due_at')
    valid = date.is_a?(String) && date.size <= 60 && date.match?(/(?:Z|[+-]\d{2}:\d{2})\z/)
    raise ArgumentError, 'Explicit ISO activity date and offset required' unless valid

    Time.iso8601(date)
  end

  def authorize_customer!(row)
    Pundit.authorize(@context.native.to_h, @ticket, :view_customer?)
    @context.access.contact(@ticket.requester_id)
    valid = row.contact_id == @ticket.requester_id && (!row.company_id || row.company_id == @ticket.company_id)
    raise Pundit::NotAuthorizedError unless valid
  end
end
