# frozen_string_literal: true

# Revalidates the original executor and complete native impact without taking reversed Account/publication locks.
class JrcContactCenter::PauseApprovalSourceCurrent
  def initialize(review)
    @review = review
  end

  def call
    return unavailable unless JrcApprovals::Ledger.digest(@review.payload) == @review.context_digest

    parent = JrcContactCenter::DeferredPauseRequest.where(account_id: @review.account_id, id: @review.deferred_pause_request_id,
                                                          account_user_id: @review.actor_account_user_id,
                                                          actor_user_id: @review.actor_user_id, state: 'pending').first!
    current = current_intent(parent)
    return unavailable unless current.fetch('required')

    { 'current' => current.fetch('payload') == @review.payload && current.fetch('digest') == @review.context_digest,
      'digest' => current.fetch('digest') }
  rescue ActiveRecord::RecordNotFound, JrcContactCenter::OperationError, Pundit::NotAuthorizedError
    unavailable
  end

  private

  def current_intent(parent)
    account = Account.find(@review.account_id)
    member = account.account_users.find(@review.actor_account_user_id)
    actor = User.find(@review.actor_user_id)
    context = { account: account, account_user: member, user: actor }
    JrcContactCenter::PauseApprovalIntent.new(context: context).call(input(parent, account, member))
  end

  def input(parent, account, member)
    parent.attributes.symbolize_keys.slice(:reason_code, :queue_id, :justification).merge(
      command_id: parent.request_id, expected_state_version: JrcContactCenter::AgentStateSnapshot.new(account_user: member).version,
      expected_request_revision: JrcContactCenter::DeferredPauseRevision.token(account: account, member: member)
    )
  end

  def unavailable
    { 'current' => false, 'digest' => 'unavailable' }
  end
end
