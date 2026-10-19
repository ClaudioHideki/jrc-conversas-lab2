class JrcRelationship::BatchExecutionJob < ApplicationJob
  queue_as :default
  retry_on ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, wait: 3.seconds, attempts: 3

  def perform(id)
    review = JrcRelationship::BatchReview.find_by(id: id)
    return unless review&.state == 'running'

    member = AccountUser.find_by!(account_id: review.account_id, user_id: review.actor_id)
    service = JrcRelationship::ReviewedPortfolioBatch.new(JrcRelationship::Context.new(member))
    result = service.advance(review.id)
    self.class.perform_later(review.id) if result.fetch('state') == 'running'
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    stop_revoked(id)
  end

  private

  def stop_revoked(id)
    # Stopping an already-approved batch cannot grant or perform native work.
    JrcRelationship::BatchReview.transaction do
      review = JrcRelationship::BatchReview.lock.find_by(id: id, state: 'running')
      next unless review

      review.items.where(state: 'pending').find_each { |item| item.update!(state: 'canceled', error_code: 'BATCH_AUTHORITY_CHANGED') }
      review.update!(state: 'attention', revision: review.revision + 1)
    end
  end
end
