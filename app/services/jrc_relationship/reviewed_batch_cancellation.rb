# Rescinding one's own remaining intent grants no customer/source read or write.
# Applied receipts and terminal snapshots remain protected by the native DB guards.
class JrcRelationship::ReviewedBatchCancellation
  def initialize(context)
    @account_id = context.account.id
    @actor_id = context.user.id
    @authority = JrcRelationship::BatchReviewAuthority.new(account_id: @account_id, actor_id: @actor_id)
  end

  def call(id, expected_revision:, reason: nil)
    raise ArgumentError, 'A whole-number current review revision is required' unless expected_revision.is_a?(Integer) && expected_revision.positive?

    JrcRelationship::BatchReview.transaction do
      @authority.call do |context|
        review = JrcRelationship::BatchReview.where(account_id: @account_id, actor_id: @actor_id).lock.find(id)
        stop_pending!(review, context, expected_revision, reason) if review.state.in?(%w[previewed running])
        block_given? ? yield(review) : review
      end
    end
  end

  private

  def stop_pending!(review, context, revision, reason)
    raise ActiveRecord::StaleObjectError.new(review, 'cancel') unless review.revision == revision

    items = review.items.where(account_id: @account_id, state: 'pending')
    count = items.count
    items.find_each { |item| item.update!(state: 'canceled') }
    review.update!(state: 'canceled', revision: review.revision + 1)
    return unless reason

    context.audit!(review, action: 'reviewed_batch_pending_canceled',
                           after: { scope: 'own_reviewed_operations', reason: reason, stopped_pending: count })
  end
end
