# frozen_string_literal: true

# Executed only for a new native paused event, after the historical command replay path.
class JrcContactCenter::PauseApprovalGate
  def initialize(account:, member:)
    @account = account
    @member = member
  end

  def call(definition:, deferred_request:)
    mandatory = JrcContactCenter::PauseCatalog.new(account: @account).enforced? && definition&.fetch('approval_required', false) == true
    recorded = deferred_request.is_a?(JrcContactCenter::DeferredPauseRequest) &&
               JrcContactCenter::PauseApprovalReview.exists?(account: @account, deferred_pause_request_id: deferred_request.id)
    return {} unless mandatory || recorded

    raise JrcContactCenter::OperationError.new('pause_approval_required', status: :conflict) unless recorded

    record = JrcContactCenter::DeferredPauseRequest.where(account: @account, account_user: @member,
                                                         actor_user_id: @member.user_id, state: 'pending').find(deferred_request.id)
    status = JrcContactCenter::PauseApprovalReadiness.new(account: @account, member: @member).call(record, lock: true)
    raise JrcContactCenter::OperationError.new('pause_approval_required', status: :conflict) unless status.fetch(:status) == 'ready'

    { 'pause_approval_context_digest' => status.fetch(:digest), 'pause_approval_scope_ids' => status.fetch(:scopes).pluck(:id) }
  end
end
