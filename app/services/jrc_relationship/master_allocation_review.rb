# An initial-allocation operation in the existing reviewed engine, not a new
# customer registry or an owner-transfer adapter. Each native item is atomic.
class JrcRelationship::MasterAllocationReview
  def initialize(context)
    @context = context
    @sources = JrcRelationship::MasterAllocationSources.new(context)
    @groups = JrcRelationship::PortfolioMembershipReview.new(context)
  end

  def snapshot(inputs, lock:)
    group, config, pin = @groups.capture_group(inputs, lock: lock)
    JrcRelationship::PortfolioGroupAccess.complete_management!(@context, group.id)
    records = @sources.records(inputs, lock: lock)
    validate_links!(group, records)
    rows = records.map { |record| @sources.pin(record).merge('linked' => linked?(group, record)) }
    minutes = config&.effective_rules&.fetch('portfolio_review_validity_minutes', 15) || 15
    { 'version' => 1, 'access_signature' => @context.access_signature, 'master_group' => pin,
      'rows' => rows, 'validity_minutes' => [15, minutes].min,
      'master_authority' => @sources.authority_pin(records, group),
      'master_capacity' => JrcRelationship::MasterAllocationCapacity.new(@context).capture(records, rows, group),
      'summary' => { 'portfolio_group_id' => group.id, 'portfolio_group_name' => group.name,
                     'create_count' => rows.count { |row| row.fetch('mode') == 'create' },
                     'reuse_count' => rows.count { |row| row.fetch('mode') == 'reuse' } } }
  end

  def validate!(review)
    stale! unless review.snapshot.fetch('access_signature') == @context.access_signature
    raise JrcRelationship::BatchReviewError.new('BATCH_REVIEW_EXPIRED', 'Reviewed master allocation expired') if review.expires_at <= Time.current

    @sources.authorize_read!(review)
    progress = JrcRelationship::MasterAllocationProgress.call(review)
    group = @groups.validate_group!(review.inputs, review.snapshot.fetch('master_group'), revision: progress.fetch(:revision))
    records = @sources.records(review.inputs, lock: true)
    validate_rows!(review, records, progress.fetch(:applied), group)
    stale! unless review.snapshot.fetch('master_authority') == @sources.authority_pin(records, group)
    validate_capacity!(review, records, group, progress)
    progress
  end

  def apply!(review, item)
    progress = validate!(review)
    original = review.snapshot.fetch('rows').fetch(item.ordinal)
    unless original['company_id'] == item.company_id
      raise JrcRelationship::BatchReviewError.new('BATCH_RECEIPT_INVALID',
                                                  'Master item identity mismatch')
    end

    assignment = allocation!(review, original)
    result = link!(review, assignment, progress.fetch(:revision))
    validate_current_actor!(review)
    { 'updated' => 1, 'operation' => 'master_allocation', 'company_id' => item.company_id, 'assignment_id' => assignment.id,
      'allocation_state' => original.fetch('mode') == 'create' ? 'created' : 'reused',
      'assignment_digest' => JrcRelationship::BatchReviewPlan.new(@context).row_snapshot(assignment).fetch('digest'),
      'portfolio_group_id' => result.fetch(:id), 'group_revision_before' => progress.fetch(:revision),
      'group_version' => result.fetch(:version), 'membership_state' => result.fetch(:results).sole.fetch(:state) }
  end

  def authorize_read!(review)
    @sources.authorize_read!(review)
  end

  private

  def validate_current_actor!(review)
    current = JrcRelationship::Context.new(@context.member.reload)
    raise Pundit::NotAuthorizedError unless current.policy.manage? && current.access_signature == review.snapshot.fetch('access_signature')
  end

  def validate_capacity!(review, records, group, progress)
    capacity = JrcRelationship::MasterAllocationCapacity.new(@context).capture(records, review.snapshot.fetch('rows'), group,
                                                                               applied: progress.fetch(:applied))
    stale! unless review.snapshot.fetch('master_capacity') == capacity
    raise ArgumentError, 'Reviewed native capacity is not available' if capacity.fetch('rows').any? { |row| row['blocker'] }
  end

  def link!(review, assignment, revision)
    result = JrcRelationship::PortfolioGroups.new(@context).set_customers!(review.inputs.fetch('portfolio_group_id'),
                                                                           ids: [assignment.id], active: true, expected_version: revision,
                                                                           reason: review.inputs.fetch('justification'))
    unless result.fetch(:id) == review.inputs.fetch('portfolio_group_id') && result.fetch(:results).sole.fetch(:assignment_id) == assignment.id
      raise JrcRelationship::BatchReviewError.new('BATCH_RECEIPT_INVALID', 'Native master membership receipt mismatch')
    end

    result
  end

  def allocation!(review, original)
    return @context.assignment(original.fetch('assignment_id'), write: true) if original.fetch('mode') == 'reuse'

    attrs = review.inputs.fetch('creations').find { |row| row.fetch('company_id') == original.fetch('company_id') }
    JrcRelationship::AssignmentCreation.new(@context).call(attrs.except('exception_reason'), exception_reason: attrs['exception_reason'])
  end

  def validate_rows!(review, records, applied, group)
    review.snapshot.fetch('rows').zip(records).each do |row, record|
      receipt = applied[row.fetch('company_id')]
      stale! unless valid_record?(record, row, receipt)
      stale! unless linked?(group, record) == (receipt ? true : row.fetch('linked'))
    end
    validate_links!(group, records)
  end

  def valid_record?(record, row, receipt)
    return @sources.pin(record) == row.except('linked') unless receipt

    record.id == receipt.fetch('assignment_id') &&
      JrcRelationship::BatchReviewPlan.new(@context).row_snapshot(record).fetch('digest') == receipt.fetch('assignment_digest')
  end

  def validate_links!(group, records)
    records.each do |record|
      link = group.customer_links.build(account: @context.account, assignment: record, active: true)
      # Existing links are valid native no-ops; do not run uniqueness on a
      # different unsaved link pointing at the same persisted assignment.
      link = group.customer_links.find_by(assignment_id: record.id) || link if record.persisted?
      link.active = true
      link.validate!
    end
  end

  def linked?(group, record)
    record.persisted? && group.customer_links.exists?(assignment_id: record.id, active: true)
  end

  def stale!
    raise JrcRelationship::BatchReviewError.new('BATCH_REVIEW_STALE', 'Reviewed master allocation changed; create a fresh review')
  end
end
