# frozen_string_literal: true

class JrcServiceDesk::TicketEventPolicy < JrcServiceDesk::TicketRecordPolicy
  # Events are created only inside an authorized domain transaction, never by an API.
  def show?
    super && JrcServiceDesk::InteractionVisibility.readable?(record, operational_context)
  end

  class Scope < JrcServiceDesk::TicketRecordPolicy::Scope
    def resolve
      JrcServiceDesk::InteractionVisibility.scope(super, operational_context)
    end
  end
end
