# No policy, approver, capacity or permission is installed automatically.
class JrcRelationship::DistributionApprovalCatalog
  FIELDS = { 'context_digest' => 'string', 'policy_context_digest' => 'string', 'evidence_state' => 'string',
             'customer_count' => 'integer', 'target_user_id' => 'integer', 'justification' => 'string' }.freeze

  def self.install!
    key = JrcRelationship::DistributionApproval::KEY
    model = JrcRelationship::BatchReview
    entries = JrcApprovals::Catalog.instance_variable_get(:@entries)
    return if entries[key]&.model.equal?(model)

    JrcApprovals::Catalog.instance_variable_get(:@mutex).synchronize { entries.delete(key) }
    JrcApprovals::Catalog.register(key: key, version: 1, model: model, fields: FIELDS,
                                   authorize: ->(actor, review) { authorized?(review, actor) },
                                   request_authorize: ->(actor, review) { review.actor_id == actor.id },
                                   capture: ->(review, actor) { capture(review, actor) },
                                   verify: ->(review, actor) { verify_source!(review, actor) })
  end

  def self.context(review, actor)
    member = review.account.account_users.find_by!(user_id: actor&.id)
    context = JrcRelationship::Context.new(member)
    raise Pundit::NotAuthorizedError unless review.inputs['operation'] == 'assign'

    JrcRelationship::PortfolioGroupConfiguration.authorize_snapshot!(context, review.snapshot)
    ids = review.inputs.fetch('ids')
    scope = JrcRelationship::ReviewedAssignmentScope.new(context, review).scope
    raise Pundit::NotAuthorizedError unless scope.where(id: ids).count == ids.size

    context
  end

  def self.authorized?(review, actor)
    context(review, actor)
    true
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    false
  end

  def self.capture(review, actor)
    current = context(review, actor)
    # Policy bindings belong to the original executor, never to an impersonated approver.
    executor = review.account.account_users.find_by!(user_id: review.actor_id)
    original = JrcRelationship::Context.new(executor)
    binding = JrcRelationship::DistributionApproval.new(original).current_binding!(review)
    valid = current_executor?(original, review) && current_source?(review, current)
    { issuer_company_id: binding.fetch('issuer_company_id'), business_unit_id: binding.fetch('business_unit_id'),
      values: { context_digest: review.digest, policy_context_digest: JrcApprovals::Ledger.digest(binding),
                evidence_state: valid ? 'current' : 'stale', customer_count: review.inputs.fetch('ids').size,
                target_user_id: review.inputs['owner_id'] || 0, justification: review.inputs['justification'].to_s } }
  end

  def self.current_executor?(original, review)
    original.user.active_for_authentication? && original.policy.manage? && original.policy.team? &&
      original.access_signature == review.snapshot.fetch('access_signature')
  end

  def self.current_source?(review, context)
    return false unless review.state.in?(%w[previewed running]) && review.expires_at > Time.current

    JrcRelationship::ResponsibilityReview.new(context).verify!(review, lock: false)

    pending = review.items.where(state: 'pending').pluck(:assignment_id)
    plan = JrcRelationship::BatchReviewPlan.new(context)
    # Read only: approval must not acquire or mutate the executor's batch/assignment locks.
    rows = context.assignments.where(id: pending).order(:id).to_a
    return false unless rows.size == pending.size

    rows.all? do |row|
      captured = review.snapshot.fetch('rows').find { |item| item.fetch('assignment_id') == row.id }
      captured == plan.row_snapshot(row)
    end
  rescue ArgumentError, Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    false
  end

  def self.verify_source!(review, actor)
    data = capture(review, actor)
    raise ArgumentError, 'Distribution origin changed or expired' unless data.fetch(:values).fetch(:evidence_state) == 'current'

    executor = context(review, review.actor)
    JrcRelationship::ResponsibilityReview.new(executor).verify!(review, lock: false)
    JrcRelationship::ResponsibilityReview.new(context(review, actor)).verify!(review, lock: false) if actor.id != review.actor_id
    JrcRelationship::DistributionCapacity.new(executor).verify!(review)
    JrcRelationship::DistributionCapacity.new(context(review, actor)).verify!(review) if actor.id != review.actor_id
    true
  end
end
