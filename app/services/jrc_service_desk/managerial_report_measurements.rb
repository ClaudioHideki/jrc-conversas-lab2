# frozen_string_literal: true

class JrcServiceDesk::ManagerialReportMeasurements
  KINDS = %w[first_response resolution].freeze

  def initialize(query, now: Time.current)
    @query = query
    @now = now
  end

  def summary(total)
    { closure: closure_summary, sla: sla_summary(total) }
  end

  def details(rows)
    ids = rows.map { |row| Integer(row.fetch(:id), 10) }
    closed = closures.where(ticket_id: ids).group(:ticket_id).maximum(:occurred_at)
    clocks = measured_clocks.where(ticket_id: ids).includes(sla_cycle: %i[lifecycle_policy_version sla_snapshot])
    clocks_by_ticket = clocks.group_by(&:ticket_id)
    rows.map do |row|
      id = Integer(row.fetch(:id), 10)
      ended = closed[id]
      row.merge(closed_at: ended&.in_time_zone(@query.timezone)&.iso8601, closure_seconds: ended && (ended - Time.iso8601(row[:opened_at])).round,
                sla: clocks_by_ticket.fetch(id, []).to_h { |clock| [clock.kind, clock_detail(clock)] })
    end
  end

  private

  def closure_summary
    durations = closures.group(:ticket_id)
                        .select(Arel.sql('EXTRACT(EPOCH FROM MAX(occurred_at) - MIN(jrc_service_desk_tickets.opened_at)) AS seconds'))
    count, mean = JrcServiceDesk::LifecycleTransition.from(durations, :durations).pick(Arel.sql('COUNT(*)'), Arel.sql('AVG(seconds)'))
    { measured: count, mean_seconds: mean&.to_f }
  end

  def closures
    return JrcServiceDesk::LifecycleTransition.none unless @query.context.capability?(:history_view)

    ids = @query.relation_for('history_view').joins(:status).where(jrc_service_desk_ticket_statuses: { phase: 'closed' }).select(:id)
    JrcServiceDesk::LifecycleTransition.where(account_id: @query.context.account.id, unit_id: @query.unit.id, ticket_id: ids, action: 'close')
                                       .joins(:ticket).where('occurred_at >= jrc_service_desk_tickets.opened_at')
  end

  def measured_clocks
    return JrcServiceDesk::SlaClock.none unless @query.context.capability?(:sla_view)

    tenant = { account_id: @query.context.account.id, unit_id: @query.unit.id }
    cycles = JrcServiceDesk::SlaCycle.where(tenant).where(ticket_id: @query.relation_for('sla_view').select(:id))
                                      .group(:ticket_id).select(Arel.sql('MAX(id)'))
    active = JrcServiceDesk::SlaClock.where(tenant).where(sla_cycle_id: cycles, kind: KINDS, state: %w[running paused completed])
                                    .where.not(due_at: nil).where('budget_seconds > 0 AND elapsed_seconds >= 0')
    active.where.not(state: 'completed').or(active.where(state: 'completed').where.not(achieved_at: nil))
  end

  def sla_summary(total)
    clocks = measured_clocks
    KINDS.index_with do |kind|
      selected = clocks.where(kind: kind)
      completed = selected.where(state: 'completed')
      running = selected.where(state: %w[running paused])
      measured = selected.count
      late = completed.where('achieved_at > due_at').count
      on_time = completed.where('achieved_at <= due_at').count
      { measured: measured, unmeasured: total - measured, within: on_time, late: late,
        in_progress: running.count, overdue: JrcServiceDesk::ClockBreachQuery.ticket_count(running, now: @now),
        mean_seconds: completed.average(:elapsed_seconds)&.to_f }
    end
  end

  def clock_detail(clock)
    if clock.state == 'completed'
      return { result: clock.met? ? 'within' : 'late', seconds: clock.elapsed_seconds }
    end

    breached = JrcServiceDesk::ClockProjection.new(clock, now: @now).call[:breached]
    { result: breached ? 'overdue' : 'in_progress' }
  end
end
