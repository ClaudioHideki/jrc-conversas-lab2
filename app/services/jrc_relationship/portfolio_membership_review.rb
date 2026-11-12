class JrcRelationship::PortfolioMembershipReview
  PIN_FIELDS = %w[id account_id name objective owner_id team_id business_unit_id segment_id visibility status goals].freeze

  def initialize(context)
    @context = context
  end

  def snapshot(inputs, lock:, records:)
    group, configuration, pin = capture_group(inputs, lock: lock)
    validate_links!(group, records, inputs.fetch('active'))
    minutes = configuration&.effective_rules&.fetch('portfolio_review_validity_minutes', 15) || 15
    { 'group_membership' => pin.merge('links' => links(group, inputs.fetch('ids'))),
      'validity_minutes' => [15, minutes].min,
      'membership_capacity' => JrcRelationship::PortfolioMembershipCapacity.new(@context).capture(group, inputs, records, configuration),
      'summary' => { 'portfolio_group_id' => group.id, 'portfolio_group_name' => group.name, 'active' => inputs.fetch('active') } }
  end

  def capture_group(inputs, lock:)
    group = group!(inputs, lock: lock)
    raise ArgumentError, 'Reviewed portfolio changed' unless group.lock_version == inputs.fetch('expected_version')

    config = configuration(group)
    [group, config, { 'portfolio_group_id' => group.id, 'initial_revision' => group.lock_version, 'digest' => fingerprint(group, config) }]
  end

  def validate_group!(inputs, pin, revision:)
    group = group!(inputs, lock: true)
    valid = group.lock_version == revision && pin.fetch('digest') == fingerprint(group, configuration(group))
    raise JrcRelationship::BatchReviewError.new('BATCH_REVIEW_STALE', 'Reviewed portfolio changed') unless valid

    group
  end

  def validate!(review)
    group = group!(review.inputs, lock: true)
    pin = review.snapshot.fetch('group_membership')
    progress = JrcRelationship::PortfolioMembershipProgress.call(review)
    valid = group.lock_version == progress.fetch(:revision) && pin.fetch('digest') == fingerprint(group, configuration(group)) &&
            progress.fetch(:links) == links(group, review.inputs.fetch('ids'))
    raise JrcRelationship::BatchReviewError.new('BATCH_REVIEW_STALE', 'Reviewed portfolio changed; create a fresh review') unless valid
    return unless review.expires_at <= Time.current

    raise JrcRelationship::BatchReviewError.new('BATCH_REVIEW_EXPIRED', 'Reviewed portfolio expired; create a fresh review')
  end

  def apply!(review, item)
    revision = JrcRelationship::PortfolioMembershipProgress.call(review).fetch(:revision)
    inputs = review.inputs
    result = JrcRelationship::PortfolioGroups.new(@context).set_customers!(inputs.fetch('portfolio_group_id'),
                                                                           ids: [item.assignment_id], active: inputs.fetch('active'),
                                                                           expected_version: revision, reason: inputs.fetch('justification'))
    membership = result.fetch(:results).sole
    unless result.fetch(:id) == review.inputs.fetch('portfolio_group_id') && membership.fetch(:assignment_id) == item.assignment_id
      raise JrcRelationship::BatchReviewError.new('BATCH_RECEIPT_INVALID', 'Native portfolio membership receipt mismatch')
    end

    { 'updated' => 1, 'operation' => 'portfolio_membership', 'assignment_id' => item.assignment_id,
      'portfolio_group_id' => result.fetch(:id), 'group_revision_before' => revision,
      'group_version' => result.fetch(:version), 'membership_state' => membership.fetch(:state) }
  end

  def authorize_read!(review)
    JrcRelationship::PortfolioGroupScope.writable(@context).find(review.inputs.fetch('portfolio_group_id'))
  end

  private

  def validate_links!(group, records, active)
    JrcRelationship::PortfolioGroupConfiguration.before_unlink!(group, records.map(&:id)) unless active
    return unless active

    existing = group.customer_links.where(assignment_id: records.map(&:id)).index_by(&:assignment_id)
    records.each do |record|
      link = existing[record.id] || group.customer_links.build(account: @context.account, assignment: record)
      link.active = true
      link.validate!
    end
  end

  def group!(inputs, lock:)
    scope = JrcRelationship::PortfolioGroupScope.writable(@context)
    scope = scope.lock('FOR UPDATE NOWAIT') if lock
    group = scope.find(inputs.fetch('portfolio_group_id'))
    raise ArgumentError, 'Archived portfolios cannot change customer links' unless group.status == 'active'

    group
  end

  def configuration(group)
    JrcRelationship::Configuration.where(account_id: @context.account.id, scope_key: "portfolio:#{group.id}").lock('FOR SHARE NOWAIT').first
  end

  def fingerprint(group, config)
    JrcRelationship::PlaybookFlowReference.digest([group.attributes.slice(*PIN_FIELDS),
                                                   config&.attributes&.slice('id', 'version', 'weights', 'rules')])
  end

  def links(group, ids)
    current = group.customer_links.where(account_id: @context.account.id, assignment_id: ids, active: true).pluck(:assignment_id)
    ids.to_h { |id| [id.to_s, current.include?(id)] }
  end
end
