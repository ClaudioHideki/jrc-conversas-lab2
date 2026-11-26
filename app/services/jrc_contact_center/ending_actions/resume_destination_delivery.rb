# frozen_string_literal: true

# Delivers the same still-pending durable intent after explicit review. No new
# consent, root, retry, effect key, ACW completion or successful result is forged.
class JrcContactCenter::EndingActions::ResumeDestinationDelivery
  def initialize(account:, member:, qualification_id:, attempt_id:, review:)
    @account = account
    @member = member
    @qualification_id = qualification_id
    @attempt_id = attempt_id
    @review = JrcContactCenter::EndingActions::DestinationSelectionReview.new(review)
  end

  def call
    @review.validate!
    raise JrcContactCenter::OperationError, 'ending_execution_requires_independent_transaction' if Account.connection.transaction_open?

    origin_id, actor_id, actor_user_id = read_selected_identity
    attempt = JrcContactCenter::EndingActions::OriginalActorContext.new(account: @account, origin_id: origin_id).call do |member, origin|
      same = member.id == actor_id && member.user_id == actor_user_id && origin.source_qualification_id.to_s == @qualification_id.to_s
      raise Pundit::NotAuthorizedError unless same

      validate_pending(member, origin)
    end
    JrcContactCenter::EndingActions::DispatchDestinationAttempt.call(attempt)
    attempt
  end

  private

  def read_selected_identity
    JrcContactCenter::EndingActions::HistoryContext.new(
      account: @account, member: @member, qualification_id: @qualification_id
    ).call do |member, qualification|
      origins = JrcContactCenter::EndingActionOrigin.where(account: @account, source_qualification_id: qualification.id)
      row = JrcContactCenter::EndingDestinationAttempt.where(account: @account, origin_id: origins.select(:id)).find(@attempt_id)
      origin = origins.find(row.origin_id)
      raise Pundit::NotAuthorizedError unless origin.actor_account_user_id == member.id && origin.actor_user_id == member.user_id

      [origin.id, member.id, member.user_id]
    end
  end

  def validate_pending(member, origin)
    attempt = JrcContactCenter::EndingDestinationAttempt.where(account: @account, origin: origin).find(@attempt_id)
    @review.verify!(attempt)
    raise JrcContactCenter::OperationError.new('ending_pending_review_changed', status: :conflict) if attempt.outcome

    JrcContactCenter::EndingActions::SelectedDestinationAuthority.new(
      account: @account, member: member, origin: origin, attempt: attempt
    ).call
    attempt
  end
end
