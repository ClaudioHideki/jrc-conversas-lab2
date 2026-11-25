# frozen_string_literal: true

# One explicit, owned pending operation. Never call the qualification-wide job:
# doing so would also execute unselected rules. No terminal retry or new attempt.
class JrcContactCenter::EndingActions::RunPendingProjectAttempt
  REVIEW_FIELDS = %w[confirmed expected_request_key expected_version_id].freeze

  def initialize(account:, member:, qualification_id:, attempt_id:, review:)
    @account = account
    @member = member
    @qualification_id = qualification_id
    @attempt_id = attempt_id
    @review = review
  end

  def call
    validate_review!
    raise JrcContactCenter::OperationError, 'ending_execution_requires_independent_transaction' if Account.connection.transaction_open?

    attempt_id = reviewed_attempt_id
    # The read lock must close before the existing independent effect boundary.
    # Its original-actor command reauthorizes source and destination again.
    outcome = JrcContactCenter::EndingActions::ExecuteAttempt.new(account: @account, attempt_id: attempt_id).call
    { attempt_id: attempt_id.to_s, qualification_id: @qualification_id.to_s,
      outcome: outcome.outcome, result_code: outcome.result_code }
  end

  private

  def validate_review!
    valid = @review.is_a?(Hash) && @review.keys.sort == REVIEW_FIELDS && @review['confirmed'] == true &&
            @review['expected_request_key'].is_a?(String) && @review['expected_version_id'].is_a?(String)
    raise JrcContactCenter::OperationError, 'invalid_ending_pending_review' unless valid
  end

  def reviewed_attempt_id
    context = JrcContactCenter::EndingActions::HistoryContext.new(
      account: @account, member: @member, qualification_id: @qualification_id
    )
    context.call do |member, qualification|
      origins = JrcContactCenter::EndingActionOrigin.where(account: @account, source_qualification_id: qualification.id)
      attempt = JrcContactCenter::EndingActionAttempt.where(account: @account, origin_id: origins.select(:id)).find(@attempt_id)
      JrcContactCenter::EndingActions::PendingProjectAction.new(account: @account, member: member, attempt: attempt).call
      verify_review!(attempt)
      attempt.id
    end
  end

  def verify_review!(attempt)
    matches = @review['expected_request_key'] == attempt.request_key && @review['expected_version_id'] == attempt.version_id.to_s
    raise JrcContactCenter::OperationError.new('ending_pending_review_changed', status: :conflict) unless matches
  end
end
