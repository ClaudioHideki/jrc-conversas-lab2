# frozen_string_literal: true

# Creators, current assignees and closure actors are separate dimensions, never a
# combined productivity score. Historical audit memberships aggregate by person.
class JrcServiceDesk::OperationalWorkforceMetrics
  def initialize(query)
    @query = query
    @context = query.context
    @cohort = query.relation_for('history_view')
  end

  def call
    return nil unless @context.capability?(:history_view)

    @counts = counts
    @sla = sla_counts
    members = contributor_memberships
    { items: members.group_by(&:account_user_id).values.map { |rows| employee(rows) }, truncated: @truncated,
      definition: 'history_visible_opening_cohort_creators_current_assignees_and_period_closure_actors_not_productivity_score' }
  end

  private

  def contributor_memberships
    contributors = JrcServiceDesk::UnitMembership.where(account_id: @context.account.id, unit_id: @query.unit.id,
                                                        id: @counts.values.flat_map(&:keys).compact.uniq)
    ids = contributors.distinct.order(:account_user_id).limit(101).pluck(:account_user_id)
    @truncated = ids.size > 100
    contributors.where(account_user_id: ids.first(100)).includes(account_user: :user).order(:account_user_id)
  end

  def counts
    ownership_counts.merge(closure_counts)
  end

  def ownership_counts
    { created: @cohort.group(:created_by_membership_id).count, assigned: @cohort.group(:assignee_membership_id).count,
      pending: @cohort.joins(:status).where(jrc_service_desk_ticket_statuses: { phase: %w[open waiting] }).group(:assignee_membership_id).count }
  end

  def closure_counts
    closes = @query.activity_transitions.where(action: 'close')
    others = closes.joins(:ticket).where(<<~SQL.squish)
      jrc_service_desk_tickets.assignee_membership_id IS DISTINCT FROM jrc_service_desk_lifecycle_transitions.actor_membership_id
    SQL
    { closed: closes.group(:actor_membership_id).count, closed_for_other_assignee: others.group(:actor_membership_id).count,
      closed_by_other: others.group('jrc_service_desk_tickets.assignee_membership_id').count }
  end

  def sla_counts
    return nil unless @context.capability?(:sla_view)

    clocks = completed_resolution_clocks
    field = 'jrc_service_desk_tickets.assignee_membership_id'
    { mean: clocks.group(field).average(:elapsed_seconds), completed: clocks.group(field).count,
      breached: clocks.where('achieved_at > due_at').group(field).count }
  end

  def completed_resolution_clocks
    cohort = @context.supervision_access.scope(@cohort, permission: 'sla_view')
    cycles = JrcServiceDesk::SlaCycle.where(account_id: @context.account.id, unit_id: @query.unit.id, ticket_id: cohort.select(:id))
                                     .group(:ticket_id).select('MAX(id)')
    JrcServiceDesk::SlaClock.where(account_id: @context.account.id, unit_id: @query.unit.id, sla_cycle_id: cycles,
                                   kind: 'resolution', state: 'completed').joins(sla_cycle: :ticket)
  end

  def employee(members)
    ids = members.map(&:id)
    totals = @counts.transform_values { |counts| ids.sum { |id| counts.fetch(id, 0) } }
    person = members.first.account_user
    totals.merge(account_user_id: person.id.to_s, name: person.user.name, **employee_sla(ids))
  end

  def employee_sla(ids)
    return { resolution_mean_seconds: nil, sla_completed: nil, sla_breached: nil } unless @sla

    completed = ids.sum { |id| @sla[:completed].fetch(id, 0) }
    elapsed = ids.sum { |id| @sla[:mean][id].to_f * @sla[:completed].fetch(id, 0) }
    { resolution_mean_seconds: completed.positive? ? elapsed / completed : nil, sla_completed: completed,
      sla_breached: ids.sum { |id| @sla[:breached].fetch(id, 0) } }
  end
end
