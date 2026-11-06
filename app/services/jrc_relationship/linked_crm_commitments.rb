# Account-bound ownership query shared by withdrawal readiness and the native
# source inventory. Callers must apply CRM visibility before disclosing rows.
class JrcRelationship::LinkedCrmCommitments
  MAX_ROWS = 10_000

  def initialize(account)
    @account = account
  end

  def owned_pending_scope(owner)
    activities = @account.jrc_crm_activities.where(user: owner).where.not(status: %w[completed cancelled])
    linked = activities.where("metadata ->> 'relationship_assignment_id' IS NOT NULL")
    references = [JrcRelationship::Action.where(account: @account).select(:activity_id),
                  JrcRelationship::Qbr.where(account: @account).select(:activity_id), plan_activity_ids]
    references.each { |ids| linked = linked.or(activities.where(id: ids)) }
    linked
  end

  private

  def plan_activity_ids
    ids = plan_references.filter_map { |row| row['activity_id'] }.map { |id| Integer(id.to_s, 10) }.uniq
    unless @account.jrc_crm_activities.where(id: ids).count == ids.length
      raise ArgumentError, 'Plan activity references require an authorized native origin review'
    end

    ids
  end

  def plan_references
    plans = JrcRelationship::SuccessPlan.where(account: @account, status: %w[active paused]).limit(MAX_ROWS + 1).to_a
    raise ArgumentError, 'Too many plans for a single withdrawal review' if plans.length > MAX_ROWS

    refs = plans.flat_map { |plan| plan.goals + Array(plan.metadata['milestones']) }
    raise ArgumentError, 'Plan references require a native review before analyst withdrawal' unless refs.length <= MAX_ROWS && refs.all?(Hash)

    refs
  end
end
