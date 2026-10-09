# frozen_string_literal: true

class JrcServiceDesk::TicketNotePolicy < JrcServiceDesk::TicketRecordPolicy
  def create?
    record_unit_allowed? && parent_policy.add_note? &&
      (record.visibility == 'internal' ||
       (JrcServiceDesk::InteractionVisibility::PUBLIC.include?(record.visibility) && capability?(:customer_publish)) ||
       (record.visibility == 'technical_team' && JrcServiceDesk::InteractionVisibility.readable?(record, operational_context)))
  end

  def show?
    super && JrcServiceDesk::InteractionVisibility.readable?(record, operational_context)
  end

  class Scope < JrcServiceDesk::TicketRecordPolicy::Scope
    def resolve
      JrcServiceDesk::InteractionVisibility.scope(super, operational_context)
    end
  end
end
