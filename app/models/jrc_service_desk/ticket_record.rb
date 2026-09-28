# frozen_string_literal: true

class JrcServiceDesk::TicketRecord < JrcServiceDesk::UnitRecord
  self.abstract_class = true

  belongs_to :ticket, class_name: 'JrcServiceDesk::Ticket', optional: false
  validate :ticket_scope_is_consistent

  protected

  def ownership_columns
    super + [:ticket_id]
  end

  def ticket_scope_is_consistent
    validate_unit_reference(:ticket)
  end
end
