# frozen_string_literal: true

class JrcServiceDesk::TicketEventPolicy < JrcServiceDesk::TicketRecordPolicy
  # Events are created only inside an authorized domain transaction, never by an API.
end
