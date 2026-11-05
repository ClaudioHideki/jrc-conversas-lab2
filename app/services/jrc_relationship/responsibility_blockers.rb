# Cross-module responsibilities stay in their native workflow until a native
# transfer is available. Never silently move a shared source or its history.
class JrcRelationship::ResponsibilityBlockers
  def initialize(context)
    @context = context
  end

  def call(assignment, entries, activities)
    plans = @context.records(JrcRelationship::SuccessPlan).where(id: entries.select { |row| row['kind'] == 'plans' }.pluck('id'))
    result = reference_blockers(plans, plan_references(plans), activities)
    if JrcRelationship::CadenceEnrollment.exists?(account_id: @context.account.id, assignment_id: assignment.id, state: 'active')
      result << 'active_cadence_requires_native_review'
    end
    unless activities.all? { |row| row.metadata['relationship_assignment_id'].to_s == assignment.id.to_s }
      result << 'activity_origin_requires_native_review'
    end
    result << 'shared_activity_requires_native_review' if shared_activities?(assignment, activities)
    result.uniq
  end

  private

  def plan_references(plans)
    references = plans.flat_map { |row| row.goals + Array(row.metadata['milestones']) }
    raise ArgumentError, 'Pending responsibility references require native review' unless references.all?(Hash)

    references
  end

  def reference_blockers(plans, references, activities)
    result = []
    result << 'project_responsibility_requires_native_transfer' if plans.any?(&:project_id) || references.any? { |goal| goal['task_id'].present? }
    result << 'activity_origin_requires_native_review' if other_activities?(references, activities)
    result << 'service_ticket_requires_native_transfer' if pending_tickets?(references)
    result
  end

  def other_activities?(references, activities)
    linked = @context.account.jrc_crm_activities.where(id: references.filter_map { |row| row['activity_id'] })
                     .where.not(status: %w[completed cancelled]).where.not(id: activities.map(&:id))
    linked.exists?
  end

  def pending_tickets?(references)
    native = JrcCustomers::Visibility.new(account: @context.account, user: @context.user, account_user: @context.member)
    native.tickets.where(id: references.filter_map { |row| row['ticket_id'] }).joins(:status)
          .exists?(jrc_service_desk_ticket_statuses: { phase: %w[open waiting] })
  end

  def shared_activities?(assignment, activities)
    return false if activities.empty?

    rows = JrcRelationship::SuccessPlan.where(account_id: @context.account.id, status: %w[active paused]).where.not(assignment_id: assignment.id)
    query = 'EXISTS (SELECT 1 FROM jsonb_array_elements(goals || ' \
            "COALESCE(NULLIF(metadata -> 'milestones', 'null'::jsonb), '[]'::jsonb)) AS item(value) " \
            "WHERE item.value ->> 'activity_id' IN (?))"
    rows.exists?([query, activities.map { |row| row.id.to_s }])
  end
end
