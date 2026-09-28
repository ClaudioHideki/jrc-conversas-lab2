# frozen_string_literal: true

class JrcServiceDesk::SlaMilestonePolicy < JrcServiceDesk::TicketRecordPolicy
  # Agents may read their ticket's operational deadlines, never raw contract payloads.
  # No command calculates or marks these milestones in CP2.
end
