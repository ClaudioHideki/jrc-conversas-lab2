# Acceptance of the exact historical source behind an operational SLA projection.
# This does not grant the separate native permission to read raw contract snapshots.
class JrcNico::SlaEvidence
  SNAPSHOT_RESOURCE = 'JrcNico::OperationalSlaSnapshot'.freeze
  MILESTONE_RESOURCE = 'JrcNico::OperationalSlaMilestone'.freeze

  def initialize(account)
    @account = account
  end

  def snapshot!(snapshot)
    JrcNico::MigrationVisibility.authorize!(snapshot, account: @account)
  end

  def milestone!(milestone)
    JrcNico::MigrationVisibility.authorize!(milestone, account: @account)
  end

  def clock!(clock)
    current = JrcServiceDesk::SlaClock.where(account: @account).find(clock.id)
    cycle = JrcServiceDesk::SlaCycle.where(account: @account, ticket_id: current.ticket_id).find(current.sla_cycle_id)
    snapshot = JrcServiceDesk::SlaSnapshot.where(account: @account, ticket_id: current.ticket_id).find(cycle.sla_snapshot_id)
    snapshot!(snapshot)
  end

  def clock_visible?(clock)
    ActiveRecord::Base.uncached { clock!(clock) }
    true
  rescue ActiveRecord::RecordNotFound
    false
  end

  def clocks(scope)
    snapshots = JrcNico::MigrationVisibility.scope(JrcServiceDesk::SlaSnapshot, account: @account)
    cycles = JrcServiceDesk::SlaCycle.where(account: @account, sla_snapshot_id: snapshots.select(:id))
    scope.where(account: @account, sla_cycle_id: cycles.select(:id))
  end

  def legacy_ticket!(ticket)
    # Older saved DTOs named only the ticket. Without source IDs, no particular
    # historical snapshot can be excluded from what contributed to the result.
    ActiveRecord::Base.uncached do
      [JrcServiceDesk::SlaSnapshot, JrcServiceDesk::SlaMilestone].each do |model|
        allowed = JrcNico::MigrationVisibility.scope(model, account: @account)
        pending = model.where(account: @account, ticket_id: ticket.id).where.not(id: allowed.select(:id))
        raise ActiveRecord::RecordNotFound if pending.exists?
      end
    end
    ticket
  end
end
