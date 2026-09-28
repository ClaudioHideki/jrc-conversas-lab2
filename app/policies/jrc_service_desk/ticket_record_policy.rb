# frozen_string_literal: true

class JrcServiceDesk::TicketRecordPolicy < JrcServiceDesk::OperationalPolicy
  READ_CAPABILITIES = {
    'JrcServiceDesk::TicketNote' => :notes_view, 'JrcServiceDesk::TicketEvent' => :history_view,
    'JrcServiceDesk::TicketConversation' => :conversations_view,
    'JrcServiceDesk::SlaMilestone' => :sla_view, 'JrcServiceDesk::SlaSnapshot' => :contract_conditions_view
  }.freeze

  def index?
    any_unit_allowed? && capability?(read_capability)
  end

  def show?
    record_unit_allowed? && capability?(read_capability) && parent_policy.show?
  end

  protected

  def read_capability
    READ_CAPABILITIES.fetch(record.is_a?(Class) ? record.name : record.class.name, :unknown)
  end

  def parent_policy
    JrcServiceDesk::TicketPolicy.new(user_context, record.ticket)
  end

  class Scope < JrcServiceDesk::OperationalPolicy::Scope
    def resolve
      name = scope.respond_to?(:klass) ? scope.klass.name : scope.name
      return scope.none unless operational_context.capability?(READ_CAPABILITIES.fetch(name, :unknown))

      tickets = JrcServiceDesk::TicketPolicy::Scope.new(user_context, JrcServiceDesk::Ticket).resolve.select(:id)
      unit_scope.where(ticket_id: tickets)
    end
  end
end
