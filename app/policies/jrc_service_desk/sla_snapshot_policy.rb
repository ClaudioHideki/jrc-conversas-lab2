# frozen_string_literal: true

# Raw conditions are separate from operational SLA deadlines.
class JrcServiceDesk::SlaSnapshotPolicy < JrcServiceDesk::TicketRecordPolicy
  def create?
    record_unit_allowed? && parent_policy.show? && capability?(:sla_snapshots_record)
  end
end
