# frozen_string_literal: true

class JrcServiceDesk::TicketNotePolicy < JrcServiceDesk::TicketRecordPolicy
  def create?
    record_unit_allowed? && record.visibility == 'internal' && parent_policy.add_note?
  end
end
