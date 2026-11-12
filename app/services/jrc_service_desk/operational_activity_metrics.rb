# frozen_string_literal: true

# Opening and transition dates have different cohorts. Report the observed flow
# rather than inventing a historical backlog balance for imported legacy tickets.
class JrcServiceDesk::OperationalActivityMetrics
  DAY = Arel.sql("DATE(jrc_service_desk_lifecycle_transitions.occurred_at AT TIME ZONE 'UTC')")
  OPENED_DAY = Arel.sql("DATE(jrc_service_desk_tickets.opened_at AT TIME ZONE 'UTC')")

  def initialize(query)
    @query = query
    @transitions = query.activity_transitions
  end

  def summary
    return nil unless @query.context.capability?(:history_view)

    { opened: @query.relation.count, closures: @transitions.where(action: 'close').count,
      closed_tickets: @transitions.where(action: 'close').distinct.count(:ticket_id),
      resolutions: @transitions.where(action: 'resolve').count, reopened: @transitions.where(action: 'reopen').count,
      active_backlog: @query.activity_relation.joins(:status).where(jrc_service_desk_ticket_statuses: { phase: %w[open waiting] }).count,
      definition: 'openings_by_opened_at_transitions_by_occurred_at_in_half_open_period_and_current_active_backlog' }
  end

  def daily
    return nil unless @query.context.capability?(:history_view)

    @counts = { opened: @query.relation.group(OPENED_DAY).order(OPENED_DAY.desc).limit(367).count }
              .merge(closure_counts).merge(backlog_counts)
    days = @counts.values.flat_map(&:keys).uniq.sort.reverse
    { items: days.first(366).reverse.map { |date| day(date) }, truncated: days.size > 366,
      definition: 'observed_UTC_net_active_flow_not_reconstructed_historical_balance' }
  end

  private

  def closure_counts
    { closed: daily_counts(@transitions.where(action: 'close')), reopened: daily_counts(@transitions.where(action: 'reopen')) }
  end

  def backlog_counts
    entered = @transitions.where("payload->>'from_phase' NOT IN ('open', 'waiting') AND payload->>'to_phase' IN ('open', 'waiting')")
    exited = @transitions.where("payload->>'from_phase' IN ('open', 'waiting') AND payload->>'to_phase' NOT IN ('open', 'waiting')")
    { entered: daily_counts(entered), exited: daily_counts(exited) }
  end

  def daily_counts(relation)
    relation.group(DAY).order(DAY.desc).limit(367).count
  end

  def day(date)
    values = @counts.transform_values { |counts| counts.fetch(date, 0) }
    values.slice(:opened, :closed, :reopened).merge(date: date.iso8601, backlog_change: values[:opened] + values[:entered] - values[:exited])
  end
end
