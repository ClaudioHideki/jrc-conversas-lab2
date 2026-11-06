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
    nested_commitments!
    survey_rules = JrcRelationship::WithdrawalSurveyRules.new(@context, @membership)
    collect!('survey_rules', survey_rules.source, survey_rules.visible)
    native_sources!
    verify_viewer!
    presentation
  end

  private

  def prepare_source!(analyst_id)
    @source = @context.account.users.find(analyst_id)
    @digest = Digest::SHA256.new
    @membership = @context.account.account_users.find_by!(user_id: @source.id)
    @digest << JrcServiceDesk::CanonicalJson.dump([@context.account.id, @source.id, @membership.id, @membership.updated_at.iso8601(6),
                                                   @membership.role, @membership.custom_role_id, @membership.jrc_relationship_eligibility_version,
                                                   @membership.jrc_relationship_withdrawn_at&.iso8601(6)])
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
      relationship_withdrawn_at: @membership.jrc_relationship_withdrawn_at,
      can_withdraw_relationship: can_withdraw_relationship?,
      eligibility_version: @membership.jrc_relationship_eligibility_version,
      can_restore_relationship: @membership.jrc_relationship_withdrawn_at.present? && can_change_eligibility?,
      generated_at: Time.current }
  end

  def can_withdraw_relationship?
    @membership.jrc_relationship_withdrawn_at.nil? && @counts.values.all?(&:zero?) && can_change_eligibility?
  end

  def can_change_eligibility?
    @source.id != @context.user.id && @context.policy.configure? && @context.policy.manage? && @context.assignable_users.exists?(@source.id)
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
    linked = JrcRelationship::LinkedCrmCommitments.new(@context.account).owned_pending_scope(@source)
    collect!('activities', linked, JrcRelationship::PortfolioResponsibilities.new(@context).activity_scope)
  end

  def nested_commitments!
    plans = JrcRelationship::SuccessPlan.where(account: @context.account, status: %w[active paused])
    plan_rows = "goals || COALESCE(NULLIF(metadata -> 'milestones', 'null'::jsonb), '[]'::jsonb)"
    plans = plans.where("EXISTS (SELECT 1 FROM jsonb_array_elements(#{plan_rows}) AS item(value) WHERE item.value ->> 'owner_id' = ?)",
                        @source.id.to_s)
    collect!('plan_commitments', plans, @context.records(JrcRelationship::SuccessPlan))
    qbrs = JrcRelationship::Qbr.where(account: @context.account, status: 'scheduled')
    qbrs = qbrs.where("EXISTS (SELECT 1 FROM jsonb_array_elements(decisions) AS item(value) WHERE item.value ->> 'owner_id' = ?)", @source.id.to_s)
    collect!('qbr_commitments', qbrs, @context.records(JrcRelationship::Qbr))
  end

  def cadences!
    enrollments = JrcRelationship::AnalystCadences.responsibilities(@context.account, @source).where(state: 'active')
    collect!('cadences', enrollments, enrollments.where(assignment_id: @context.assignments.select(:id)))
  end

  def native_sources!
    native = JrcRelationship::NativeResponsibilities.new(@context)
    links = JrcRelationship::WithdrawalNativeLinks.new(@context)
    JrcRelationship::NativeResponsibilities::KINDS.each do |kind|
      source = links.restrict(kind, native.owned_pending_scope(kind, @source))
      collect!(kind, source, source.exists? ? native.owned_scope(kind, @source) : source.none)
    end
    projects = JrcProjects::Project.where(account: @context.account, owner: @source).where.not(status: %w[completed canceled])
    projects = links.restrict('projects', projects)
    collect!('projects', projects, projects.exists? ? JrcOperations::Access.projects(@context.member) : projects.none)
  end
end
