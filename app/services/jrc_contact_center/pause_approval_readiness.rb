# frozen_string_literal: true

# Read-only presentation by default; a consuming caller holds native authority, publication and request locks.
class JrcContactCenter::PauseApprovalReadiness
  def initialize(account:, member:)
    @account = account
    @member = member
  end

  def call(record, lock: false)
    validate_record!(record, lock)
    review = JrcContactCenter::PauseApprovalReview.find_by(account: @account, deferred_pause_request_id: record.id)
    return { required: false, status: 'legacy', scopes: [] } unless review

    JrcApprovals::Ledger.lock!(@account.id, 'publication') if lock
    review_status(review, lock)
  end

  private

  def validate_record!(record, lock)
    raise ActiveRecord::RecordNotFound unless record.account_id == @account.id && record.account_user_id == @member.id
    raise JrcContactCenter::OperationError, 'pause_approval_transaction_required' if lock && !ApplicationRecord.connection.transaction_open?
  end

  def review_status(review, lock)
    return unavailable unless JrcContactCenter::PauseApprovalSourceCurrent.new(review).call.fetch('current')

    scopes = review.scopes.where(account: @account).order(:id).to_a
    return unavailable unless scopes_complete?(review, scopes)

    rows = scopes.map { |scope| scope_readiness(scope, lock) }
    { required: true, status: rows.all? { |row| row.fetch(:status) == 'ready' } ? 'ready' : 'approval_required',
      digest: review.context_digest, scopes: rows, local_only: true, provider_confirmed: false }
  end

  def context
    { account: @account, account_user: @member, user: @member.user }
  end

  def scopes_complete?(review, scopes)
    captured = review.payload.fetch('coverage').fetch('groups')
    scopes.any? && scopes.size == captured.size && captured.all? do |group|
      scopes.any? do |scope|
        matches_scope?(scope, group)
      end
    end
  end

  def matches_scope?(scope, group)
    scope.issuer_company_id.to_s == group.fetch('issuer_company_id') &&
      scope.business_unit_id&.to_s == group.fetch('business_unit_id') && scope.unit_ids == group.fetch('unit_ids')
  end

  def scope_readiness(scope, lock)
    check = JrcContactCenter::PauseApprovalPolicyCheck.new(context: context, lock: lock).call(scope_id: scope.id)
    check.merge(id: scope.id.to_s, issuer_company_id: scope.issuer_company_id.to_s,
                business_unit_id: scope.business_unit_id&.to_s, unit_ids: scope.unit_ids)
  end

  def unavailable
    { required: true, status: 'review_required', scopes: [], local_only: true, provider_confirmed: false }
  end
end
