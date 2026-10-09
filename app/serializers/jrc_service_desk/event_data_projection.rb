# frozen_string_literal: true

class JrcServiceDesk::EventDataProjection
  NOTE_EVENTS = %w[interaction_republished].freeze
  TASK_EVENTS = %w[task_created task_updated].freeze
  DELIVERY_EVENTS = %w[notification_delivery_updated notification_resend_requested].freeze
  CAPABILITIES = {
    'operational_rule_applied' => :sla_view,
    'note_added' => :notes_view, 'approval_requested' => :approvals_view, 'approval_decided' => :approvals_view,
    'incident_linked' => :incidents_manage, 'incident_updated' => :incidents_manage,
    'sla_snapshot_recorded' => :sla_view, 'first_response_recorded' => :sla_view,
    'clock_threshold_reached' => :sla_view, 'clock_violated' => :sla_view, 'approval_escalated' => :approvals_view,
    'resource_linked' => :incidents_manage, 'resource_updated' => :incidents_manage, 'resource_archived' => :incidents_manage
  }.freeze

  def initialize(context)
    @context = JrcServiceDesk::OperationalContext.new(context)
  end

  def call(record)
    data = record.data.slice(*JrcServiceDesk::Presenter::EVENT_FIELDS.fetch(record.event_type, []))
    return {} unless capability_allowed?(record) && sources_allowed?(record, data) && conversation_allowed?(record, data)

    redact(record, data)
  end

  private

  def capability_allowed?(record)
    required = CAPABILITIES[record.event_type]
    !required || @context.capability?(required)
  end

  def sources_allowed?(record, data)
    return note_allowed?(record, data) if NOTE_EVENTS.include?(record.event_type)
    return scoped_record(record, JrcServiceDesk::TicketTask, data['task_id']) if TASK_EVENTS.include?(record.event_type)
    return delivery_allowed?(record, data) if DELIVERY_EVENTS.include?(record.event_type)

    true
  end

  def scoped_record(event, model, id)
    row = model.find_by(id: id, account_id: event.account_id, unit_id: event.unit_id, ticket_id: event.ticket_id)
    row && Pundit.policy!(@context.to_h, row).show? && row
  end

  def note_allowed?(record, data)
    return false unless scoped_record(record, JrcServiceDesk::TicketNote, data['note_id'])

    data.delete('previous_note_id') unless scoped_record(record, JrcServiceDesk::TicketNote, data['previous_note_id'])
    true
  end

  def delivery_allowed?(record, data)
    row = JrcServiceDesk::NotificationDelivery.find_by(id: data['delivery_id'], account_id: record.account_id,
                                                       unit_id: record.unit_id, ticket_id: record.ticket_id)
    return false unless row && JrcServiceDesk::DeliveryAccess.new(@context).allowed?(row)
    return true unless data['original_delivery_id']

    original = row.original_delivery
    original && original.id.to_s == data['original_delivery_id'].to_s && JrcServiceDesk::DeliveryAccess.new(@context).allowed?(original)
  end

  def conversation_allowed?(record, data)
    return true unless %w[conversation_linked first_response_recorded].include?(record.event_type)
    return false unless @context.capability?(:conversations_view)

    conversation = Conversation.find_by(account_id: @context.account.id, id: data['conversation_id'])
    conversation && Pundit.policy!(@context.to_h, conversation).show?
  end

  def redact(record, data)
    allowed = @context.capability?(:customers_view) && JrcCustomers::DirectoryPolicy.new(@context.to_h, :directory).access?
    data.delete('company_id') unless allowed
    data.delete('cycle_id') if record.event_type == 'lifecycle_transitioned' && !@context.capability?(:sla_view)
    data
  end
end
