# Internal execution continuity for this review's immutable, applied receipts.
# This does not grant the original actor access to transferred customer data.
class JrcRelationship::ReviewedAssignmentScope
  def initialize(context, review)
    @context = context
    @review = review
  end

  def limited?
    return false if missing_ids.empty?

    verify_receipts!
    true
  end

  def scope
    return @context.assignments unless limited?

    owner_id = @review.inputs['owner_id']
    raise Pundit::NotAuthorizedError unless owner_id && @context.assignable_users.exists?(owner_id)

    JrcRelationship::BatchReviewAuthority.new(account_id: @context.account.id, actor_id: owner_id, write: false).call do |target|
      @context.assignments.or(received_assignments(target, owner_id))
    end
  end

  private

  def received_assignments(target, owner_id)
    expected = @review.snapshot.dig('distribution_approval', 'destination_access_signature')
    raise Pundit::NotAuthorizedError unless expected.present? && target.access_signature == expected

    received = target.assignments.where(id: missing_ids, owner_id: owner_id)
    raise Pundit::NotAuthorizedError unless received.count == missing_ids.length

    received
  end

  def missing_ids
    @missing_ids ||= @review.inputs.fetch('ids') - @context.assignments.where(id: @review.inputs.fetch('ids')).pluck(:id)
  end

  def verify_receipts!
    verify_actor!
    items = @review.items.where(state: 'applied', assignment_id: missing_ids).to_a
    valid = items.map(&:assignment_id).sort == missing_ids.sort && items.all? { |item| valid_receipt?(item) }
    raise Pundit::NotAuthorizedError unless valid
  end

  def verify_actor!
    expected = { 'account_id' => @context.account.id, 'actor_id' => @context.user.id }
    raise Pundit::NotAuthorizedError unless @review.attributes.slice(*expected.keys) == expected

    allowed = @review.inputs['operation'] == 'assign' && @review.state.in?(%w[running completed canceled attention]) &&
              @context.policy.manage? && @context.access_signature == @review.snapshot.fetch('access_signature')
    raise Pundit::NotAuthorizedError unless allowed
  end

  def valid_receipt?(item)
    receipt = item.receipt
    identity = { 'operation' => 'assign', 'assignment_id' => item.assignment_id }
    return false unless receipt.is_a?(Hash) && receipt.slice(*identity.keys) == identity

    expected = { 'resource_type' => 'JrcRelationship::Assignment', 'resource_id' => item.assignment_id,
                 'owner_id' => @review.inputs['owner_id'] }
    Array(receipt['resources']).any? do |row|
      row.is_a?(Hash) && row.slice(*expected.keys) == expected
    end
  end
end
