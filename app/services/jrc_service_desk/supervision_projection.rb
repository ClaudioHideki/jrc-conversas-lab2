# frozen_string_literal: true

class JrcServiceDesk::SupervisionProjection
  def initialize(context:, relation:)
    @context = JrcServiceDesk::OperationalContext.new(context)
    @relation = relation
  end

  def call
    return nil unless @context.capability?(:dashboard_view) &&
                      (@context.capability?(:tickets_view_all) || @context.supervision_access.any?('dashboard_view'))

    @relation = @context.supervision_access.scope(@relation, permission: 'dashboard_view')

    { sla: sla, sla_coverage: coverage, by_agent: agent_loads, capacity: capacities, tasks: tasks, approvals: approvals,
      evolution: evolution, top_categories: top_categories, timezone: 'UTC',
      availability: { csat: 'shared_survey_report', calendar_required: calendar_required? } }
  end

  private

  def ids
    @ids ||= @relation.select(:id)
  end

  def cycles
    @cycles ||= JrcServiceDesk::SlaCycle.where(account_id: @context.account.id, ticket_id: sla_relation.select(:id)).group(:ticket_id).maximum(:id).values
  end

  def sla_relation
    @context.supervision_access.scope(@relation, permission: 'sla_view')
  end

  def active(relation)
    relation.joins(:status).where(jrc_service_desk_ticket_statuses: { phase: %w[open waiting] })
  end

  def sla
    return nil unless @context.capability?(:sla_view) && cycles.any?

    clocks = JrcServiceDesk::SlaClock.where(account_id: @context.account.id, sla_cycle_id: cycles)
    completed = clocks.where(state: 'completed')
    { observed_cycles: cycles.length,
      running_breached: JrcServiceDesk::ClockBreachQuery.count(clocks),
      completed_met: completed.where('achieved_at <= due_at').count,
      completed_breached: completed.where('achieved_at > due_at').count,
      first_response_average_seconds: completed.where(kind: 'first_response').average(:elapsed_seconds)&.to_f,
      attendance_average_seconds: completed.where(kind: 'attendance').average(:elapsed_seconds)&.to_f,
      resolution_average_seconds: completed.where(kind: 'resolution').average(:elapsed_seconds)&.to_f }
  end

  def calendar_required?
    return false unless @context.capability?(:sla_view)

    # Group identical selectors; do not turn missing observations into a universal SLA requirement.
    sla_relation.distinct.pluck(:unit_id, :service_id, :lifecycle_policy_version_id).any? do |unit_id, service_id, version_id|
      ticket = JrcServiceDesk::Ticket.new(account_id: @context.account.id, unit_id: unit_id,
                                         service_id: service_id, lifecycle_policy_version_id: version_id)
      JrcServiceDesk::LifecycleSelector.new(ticket).applicable&.definition&.dig('sla', 'mode') == 'calendar_snapshot'
    end
  end

  def coverage
    return nil unless @context.capability?(:sla_view)

    total = sla_relation.count
    pending = JrcServiceDesk::LifecycleTransition.where(account_id: @context.account.id, ticket_id: sla_relation.select(:id))
                .where("payload->'sla'->>'calculation_pending' = 'true'").distinct.count(:ticket_id)
    completed = JrcServiceDesk::SlaClock.where(account_id: @context.account.id, sla_cycle_id: cycles, state: 'completed')
    { total_tickets: total, measured_tickets: cycles.length, unmeasured_tickets: total - cycles.length,
      tickets_with_pending_result: pending, completed_clocks: completed.count,
      met_clocks: completed.where('achieved_at <= due_at').count,
      breached_clocks: completed.where('achieved_at > due_at').count }
  end

  def agent_loads
    active(@relation).group(:assignee_membership_id).count.map do |membership_id, count|
      member = JrcServiceDesk::UnitMembership.find_by(account_id: @context.account.id, id: membership_id)
      { id: membership_id&.to_s, account_user_id: member&.account_user_id&.to_s, unit_id: member&.unit_id&.to_s,
        name: member&.account_user&.user&.name, count: count }
    end
  end

  def tasks
    scope = JrcServiceDesk::TicketTaskPolicy::Scope.new(@context.to_h, JrcServiceDesk::TicketTask).resolve.where(ticket_id: ids)
    return nil unless @context.capability?(:tasks_view)

    open = scope.where(status: %w[open in_progress])
    { open: open.count, overdue: open.where('due_at < ?', Time.current).count }
  end

  def approvals
    scope = JrcServiceDesk::TicketApprovalPolicy::Scope.new(@context.to_h, JrcServiceDesk::TicketApproval).resolve.where(ticket_id: ids)
    return nil unless @context.capability?(:approvals_view)

    pending = scope.where(status: 'pending')
    { pending: pending.count, overdue: pending.where('due_at < ?', Time.current).count }
  end

  def evolution
    counts = @relation.where('jrc_service_desk_tickets.created_at >= ?', 90.days.ago)
                      .group(Arel.sql("(jrc_service_desk_tickets.created_at AT TIME ZONE 'UTC')::date")).count
    counts.sort_by { |date, _| date }.map { |date, count| { date: date.iso8601, count: count } }
  end

  def top_categories
    counts = @relation.left_joins(:category).group('jrc_service_desk_categories.id', 'jrc_service_desk_categories.name').count
    counts.sort_by { |(id, _name), count| [-count, id || 0] }.first(10).map do |(id, name), count|
      { id: id&.to_s, name: name, count: count }
    end
  end

  def capacities
    units = @relation.reselect(:unit_id).distinct
    grants = JrcServiceDesk::UnitMembership.operational.where(account_id: @context.account.id, unit_id: units, active: true).includes(account_user: :user)
    if @context.supervision_access.memberships.exists?
      # Supervisors see only staffing represented in their authorized ticket domain.
      restricted = grants.where(unit_id: @context.supervision_access.restricted_units, id: @relation.select(:assignee_membership_id))
      grants = grants.where.not(unit_id: @context.supervision_access.restricted_units).or(restricted)
    end
    scope = JrcServiceDesk::TicketPolicy::Scope.new(@context.to_h, JrcServiceDesk::Ticket).resolve.where(unit_id: units)
    loads = active(scope).group(:assignee_membership_id).count
    grants.order(:id).map { |row| capacity(row, loads.fetch(row.id, 0)) }
  end

  def capacity(membership, load)
    { id: membership.id.to_s, unit_id: membership.unit_id.to_s, name: membership.account_user.user.name,
      availability: membership.availability, capacity: membership.capacity, active_tickets: load }
  end
end
