# A domain gate over the existing Central. Manual batch confirmation is not a vote.
class JrcRelationship::DistributionApproval
  KEY = 'relationship.portfolio_distribution'.freeze

  def initialize(context)
    @context = context
  end

  def binding(records, owner_id: nil)
    JrcRelationship::DistributionPolicyBinding.new(@context).call(records, owner_id: owner_id)
  end

  def check!(review)
    return unless review.inputs['operation'] == 'assign'

    current = current_binding!(review)
    return unless current.fetch('required')

    JrcApprovals::Authorization.new(account: @context.account, user: @context.user).member!
    JrcApprovals::Ledger.lock!(@context.account.id, 'publication')
    snapshot = JrcApprovals::Catalog.snapshot(account: @context.account, user: @context.user, key: KEY, resource_id: review.id)
    approved_request_ids(review, snapshot)
  end

  def request!(review, digest:, idempotency_key:)
    raise ArgumentError, 'Review identity mismatch' unless review.digest == digest
    raise ArgumentError, 'Review is not available' unless review.state == 'previewed'
    raise ArgumentError, 'Formal approval is not required' unless current_binding!(review).fetch('required')

    JrcRelationship::DistributionApprovalCatalog.verify_source!(review, @context.user)
    JrcApprovals::Requests.new(account: @context.account, user: @context.user)
                          .create!(key: KEY, resource_id: review.id, idempotency_key: idempotency_key)
  end

  def projection(review)
    return unless review.inputs['operation'] == 'assign'

    current = current_binding!(review)
    return { required: false, state: 'not_required', requests: [] } unless current.fetch('required')
    return { required: true, state: 'unavailable', requests: [] } unless @context.account.feature_enabled?('jrc_approvals')

    { required: true, state: projection_state(review), requests: readable_requests(review), policy_version_ids: selected_version_ids(review) }
  rescue ArgumentError, ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
    { required: true, state: 'stale', requests: [] }
  end

  def current_binding!(review)
    scope = JrcRelationship::ReviewedAssignmentScope.new(@context, review).scope
    rows = scope.where(id: review.inputs.fetch('ids')).order(:id).to_a
    raise ActiveRecord::RecordNotFound unless rows.size == review.inputs.fetch('ids').size

    current = binding(rows, owner_id: review.inputs['owner_id'])
    captured = review.snapshot['distribution_approval']
    raise ArgumentError, 'Distribution policy changed. Create a new review.' if captured ? captured != current : current.fetch('required')

    current
  end

  def self.direct_allowed!(context, records, owner_id: nil)
    ids = records.map(&:id)
    authority = JrcRelationship::BatchReviewAuthority.new(account_id: context.account.id, actor_id: context.user.id)
    authority.call do |current|
      raise Pundit::NotAuthorizedError unless current.policy.team?

      rows = current.assignments.where(id: ids).order(:id).to_a
      raise ActiveRecord::RecordNotFound unless rows.size == ids.size

      binding = new(current).binding(rows, owner_id: owner_id)
      raise ArgumentError, 'Use the reviewed transfer and formal Central approval' if binding.fetch('required')
    end
  end

  def self.lock_configuration!(account_id)
    JrcApprovals::Ledger.lock!(account_id, 'relationship_configuration')
  end

  def self.try_lock_configuration!(account_id)
    JrcApprovals::Ledger.try_lock!(account_id, 'relationship_configuration')
  end

  private

  def approved_request_ids(review, snapshot)
    versions = JrcApprovals::Selection.call(account: @context.account, key: KEY, snapshot: snapshot)
    rows = requests(review).lock.to_a
    versions.map do |version|
      latest = rows.reverse.find { |row| row.policy_version_id == version.id }
      unless JrcApprovals::RequestVerification.approved?(latest, version, snapshot)
        raise ArgumentError, 'Formal Central approval is required before executing this transfer'
      end

      latest.id
    end
  end

  def approved_now?(review)
    review.state.in?(%w[previewed running]) && check!(review).present?
  rescue JrcApprovals::Error, ArgumentError, Pundit::NotAuthorizedError
    false
  end

  def projection_state(review)
    return 'executed' if review.state == 'completed'
    return 'stale' unless JrcRelationship::DistributionApprovalCatalog.current_source?(review, @context)

    approved_now?(review) ? 'approved' : 'required'
  end

  def readable_requests(review)
    requests(review).filter_map do |row|
      JrcApprovals::RequestVisibility.authorize!(account: @context.account, user: @context.user, record: row)
      { id: row.id, state: row.state, policy_version_id: row.policy_version_id }
    rescue Pundit::NotAuthorizedError
      nil
    end
  end

  def selected_version_ids(review)
    snapshot = JrcApprovals::Catalog.snapshot(account: @context.account, user: @context.user, key: KEY, resource_id: review.id)
    JrcApprovals::Selection.call(account: @context.account, key: KEY, snapshot: snapshot).map(&:id)
  rescue JrcApprovals::Error, ArgumentError, Pundit::NotAuthorizedError
    []
  end

  def requests(review)
    JrcApprovals::Request.where(account_id: @context.account.id, module_key: 'relationship', event_key: 'portfolio_distribution',
                                resource_type: review.class.name, resource_id: review.id).order(:id)
  end
end
