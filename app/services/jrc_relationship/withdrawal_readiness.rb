require 'openssl'

# Read-only, viewer-scoped inventory. This is never permission to remove a
# member: execution must revalidate destinations, receipts and native grants.
class JrcRelationship::WithdrawalReadiness
  MAX_ROWS = 10_000

  def initialize(context)
    @context = context
  end

  def call(analyst_id)
    raise Pundit::NotAuthorizedError unless @context.policy.team?

    prepare_source!(analyst_id)
    allocations!
    responsibilities!
    native_sources!
    verify_viewer!
    presentation
  end

  private

  def prepare_source!(analyst_id)
    @source = @context.account.users.find(analyst_id)
    @digest = Digest::SHA256.new
    membership = @context.account.account_users.find_by!(user_id: @source.id)
    @digest << JrcServiceDesk::CanonicalJson.dump([@context.account.id, @source.id, membership.id, membership.updated_at.iso8601(6)])
    @counts = {}
    @signature = @context.access_signature
  end

  def verify_viewer!
    current = JrcRelationship::Context.new(@context.member)
    raise Pundit::NotAuthorizedError unless current.policy.team? && current.access_signature == @signature
  end

  def presentation
    key = Rails.application.key_generator.generate_key('relationship-withdrawal-readiness-v1', 32)
    { analyst_id: @source.id, counts: @counts, state: @counts.values.all?(&:zero?) ? 'ready_for_final_review' : 'pending_responsibilities',
      final_removal_available: false, snapshot_digest: OpenSSL::HMAC.hexdigest('SHA256', key, @digest.hexdigest + @signature),
      generated_at: Time.current }
  end

  def collect!(kind, source, visible)
    raise Pundit::NotAuthorizedError if source.where.not(id: visible.select(:id)).exists?

    refs = source.order(:id).limit(MAX_ROWS + 1).pluck(:id, :updated_at)
    raise ArgumentError, 'Too many responsibilities for one withdrawal review; use controlled scoped batches' if refs.length > MAX_ROWS

    refs.each { |id, stamp| @digest << JrcServiceDesk::CanonicalJson.dump([kind, id, stamp&.iso8601(6)]) }
    @counts[kind] = refs.length
  end

  def allocations!
    source = JrcRelationship::Assignment.where(account: @context.account, owner: @source,
                                               status: JrcRelationship::DistributionCapacityGuard::LOAD_STATUSES)
    collect!('allocations', source, @context.assignments)
  end

  def responsibilities!
    JrcRelationship::PortfolioResponsibilities::TYPES.each do |kind, (model, statuses)|
      collect!(kind, model.where(account: @context.account, owner: @source, status: statuses), @context.records(model))
    end
    activities!
    cadences!
  end

  def activities!
    activities = @context.account.jrc_crm_activities.where(user: @source).where.not(status: %w[completed cancelled])
    linked = activities.where("metadata ->> 'relationship_assignment_id' IS NOT NULL")
    activity_references.each { |ids| linked = linked.or(activities.where(id: ids)) }
    collect!('activities', linked, JrcRelationship::PortfolioResponsibilities.new(@context).activity_scope)
  end

  def activity_references
    [JrcRelationship::Action.where(account: @context.account).select(:activity_id),
     JrcRelationship::Qbr.where(account: @context.account).select(:activity_id), plan_activity_ids]
  end

  def cadences!
    enrollments = JrcRelationship::CadenceEnrollment.where(account: @context.account, state: 'active')
                                                    .joins(:batch_review).where(jrc_relationship_batch_reviews: { actor_id: @source.id })
    collect!('cadences', enrollments, enrollments.where(assignment_id: @context.assignments.select(:id)))
  end

  def plan_activity_ids
    ids = plan_references.filter_map { |row| row['activity_id'] }.map { |id| Integer(id.to_s, 10) }.uniq
    unless @context.account.jrc_crm_activities.where(id: ids).count == ids.length
      raise ArgumentError, 'Plan activity references require an authorized native origin review'
    end

    ids
  end

  def plan_references
    plans = JrcRelationship::SuccessPlan.where(account: @context.account, status: %w[active paused]).limit(MAX_ROWS + 1).to_a
    raise ArgumentError, 'Too many plans for a single withdrawal review' if plans.length > MAX_ROWS

    refs = plans.flat_map { |plan| plan.goals + Array(plan.metadata['milestones']) }
    raise ArgumentError, 'Plan references require a native review before analyst withdrawal' unless refs.length <= MAX_ROWS && refs.all?(Hash)

    refs
  end

  def native_sources!
    native = JrcRelationship::NativeResponsibilities.new(@context)
    JrcRelationship::NativeResponsibilities::KINDS.each do |kind|
      source = native_owned_source(native, kind)
      collect!(kind, source, source.exists? ? native.owned_scope(kind, @source) : source.none)
    end
    projects = JrcProjects::Project.where(account: @context.account, owner: @source).where.not(status: %w[completed canceled])
    collect!('projects', projects, projects.exists? ? JrcOperations::Access.projects(@context.member) : projects.none)
  end

  def native_owned_source(native, kind)
    source = native.pending_scope(kind)
    return source.where(assignee_id: @source.id) if kind == 'project_tasks'

    member = @context.account.account_users.find_by!(user_id: @source.id)
    source.where(assignee_membership_id: JrcServiceDesk::UnitMembership.where(account: @context.account, account_user_id: member.id).select(:id))
  end
end
