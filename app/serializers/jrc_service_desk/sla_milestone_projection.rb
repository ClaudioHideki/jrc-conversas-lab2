# frozen_string_literal: true

class JrcServiceDesk::SlaMilestoneProjection
  def initialize(record)
    @record = record
  end

  def call
    { id: @record.id.to_s, account_id: @record.account_id.to_s, unit_id: @record.unit_id.to_s, ticket_id: @record.ticket_id.to_s,
      kind: @record.kind, due_at: @record.due_at&.iso8601(6), achieved_at: @record.achieved_at&.iso8601(6),
      calculated_at: @record.calculated_at&.iso8601(6), calculator_version: @record.calculator_version,
      permissions: { show: true }, snapshot_version: @record.sla_snapshot.version, met: @record.met?,
      calculation_pending: @record.calculation_pending? }
  end
end
