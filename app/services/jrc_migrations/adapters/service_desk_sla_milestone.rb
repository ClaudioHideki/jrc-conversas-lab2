class JrcMigrations::Adapters::ServiceDeskSlaMilestone < JrcMigrations::Adapters::ServiceDeskRecord
  def model
    JrcServiceDesk::SlaMilestone
  end

  private

  def resolve_relations!(record, data)
    resolve_ticket!(record, data)
    bind_legacy_reference!(record, data, field: 'sla_snapshot_id', legacy_field: 'sla_snapshot_legacy_id', domain: 'service_desk_sla_snapshots')
    assign_historical_times!(record, data, %w[due_at calculated_at achieved_at])
  end
end
