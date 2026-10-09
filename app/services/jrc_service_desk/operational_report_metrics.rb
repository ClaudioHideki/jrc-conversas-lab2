# frozen_string_literal: true

class JrcServiceDesk::OperationalReportMetrics
  def initialize(query)
    @query = query
    @relation = query.relation
    @context = query.context
  end

  def call
    { observed_at: Time.current.iso8601(6), cohort: 'authorized_tickets_opened_in_half_open_period', total: @relation.count,
      by_unit: grouped('unit_id'), by_service: grouped('service_id'), by_origin: grouped('origin_channel'),
      by_category: grouped('category_id'), by_priority: grouped('priority_id'),
      by_customer: @query.customer_dimension? ? grouped('company_id') : nil, by_channel: channel_counts,
      phases: @relation.joins(:status).group('jrc_service_desk_ticket_statuses.phase').count,
      reopen: reopen_metrics, sla: sla_metrics,
      fcr: { value: nil, reason: 'approved_first_contact_resolution_definition_required' },
      quality: { value: nil, reason: 'approved_quality_definition_required' },
      dimension_limit: 100, channel_counts_overlap: true }
  end

  private

  def grouped(field)
    @relation.group(field).order(Arel.sql('COUNT(*) DESC')).limit(101).count.map do |id, count|
      { id: id&.to_s, count: count }
    end.then { |rows| { items: rows.first(100), truncated: rows.length > 100 } }
  end

  def channel_counts
    links = @query.channels
    return nil unless links

    links.group('inboxes.channel_type').distinct.count(:ticket_id).map { |channel, count| { channel_type: channel, count: count } }
  end

  def reopen_metrics
    return nil unless @context.capability?(:history_view)

    scope = JrcServiceDesk::LifecycleTransition.where(account_id: @context.account.id, unit_id: @query.unit.id, ticket_id: @relation.select(:id))
    scope = @query.during(scope, 'occurred_at')
    reopened = scope.where(action: 'reopen')
    { events: reopened.count, tickets: reopened.distinct.count(:ticket_id), cohort_ticket_count: @relation.count,
      cohort_reopen_percentage: @relation.exists? ? 100.0 * reopened.distinct.count(:ticket_id) / @relation.count : nil,
      closed_tickets: scope.where(action: 'close').distinct.count(:ticket_id),
      definition: 'observed_reopen_events_in_period_for_ticket_cohort_not_FCR' }
  end

  def sla_metrics
    return nil unless @context.capability?(:sla_view)

    cycles = JrcServiceDesk::SlaCycle.where(account_id: @context.account.id, unit_id: @query.unit.id, ticket_id: @relation.select(:id))
                                     .group(:ticket_id).select('MAX(id)')
    clocks = JrcServiceDesk::SlaClock.where(account_id: @context.account.id, unit_id: @query.unit.id, sla_cycle_id: cycles)
    %w[first_response attendance resolution].to_h do |kind|
      selected = clocks.where(kind: kind)
      completed = selected.where(state: 'completed')
      [kind, { observed: selected.count, completed: completed.count,
               mean_elapsed_seconds: completed.average(:elapsed_seconds)&.to_f,
               completed_breached: completed.where('achieved_at > due_at').count,
               running_overdue: selected.where(state: 'running').where('due_at < ?', Time.current).count,
               basis: 'latest_native_cycle_clock_elapsed_seconds', missing_is_not_zero: true }]
    end
  end
end
