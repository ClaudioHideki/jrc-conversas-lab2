# frozen_string_literal: true

# Called only inside the canonical Account/member authority transaction. All scope requests commit or roll back together.
class JrcContactCenter::PauseApprovalCoordinator
  def initialize(account:, member:)
    @account = account
    @member = member
  end

  def prepare!(values, expected_digest:)
    intent = JrcContactCenter::PauseApprovalIntent.new(context: context).call(values)
    return intent unless intent.fetch('required')

    valid = expected_digest.is_a?(String) && /\A[0-9a-f]{64}\z/.match?(expected_digest) &&
            ActiveSupport::SecurityUtils.secure_compare(expected_digest, intent.fetch('digest'))
    raise JrcContactCenter::OperationError.new('pause_approval_review_required', status: :conflict) unless valid

    intent
  end

  def create!(record, intent)
    return unless intent.fetch('required')
    raise JrcContactCenter::OperationError, 'pause_approval_transaction_required' unless ApplicationRecord.connection.transaction_open?

    JrcApprovals::Ledger.lock!(@account.id, 'publication')
    review = JrcContactCenter::PauseApprovalReview.create!(
      account: @account, deferred_pause_request_id: record.id, actor_account_user_id: @member.id, actor_user_id: @member.user_id,
      payload: intent.fetch('payload'), context_digest: intent.fetch('digest')
    )
    scopes = intent.fetch('payload').fetch('coverage').fetch('groups').map { |group| create_scope!(review, group) }
    scopes.each { |scope| require_policies!(scope) }
    request_all!(record, scopes)
    review
  end

  private

  def context
    { account: @account, account_user: @member, user: @member.user }
  end

  def create_scope!(review, group)
    review.scopes.create!(account: @account, issuer_company_id: group.fetch('issuer_company_id').to_i,
                          business_unit_id: group.fetch('business_unit_id')&.to_i, unit_ids: group.fetch('unit_ids'))
  end

  def require_policies!(scope)
    key = JrcContactCenter::PauseApprovalPolicyCheck::KEY
    snapshot = JrcApprovals::Catalog.snapshot(account: @account, user: @member.user, key: key, resource_id: scope.id, purpose: :request)
    versions = JrcApprovals::Selection.call(account: @account, key: key, snapshot: snapshot)
    raise JrcContactCenter::OperationError.new('pause_approval_policy_missing', status: :conflict) if versions.empty?
  rescue JrcApprovals::Error => e
    raise unless e.code == 'POLICY_REQUIRED'

    raise JrcContactCenter::OperationError.new('pause_approval_policy_missing', status: :conflict)
  end

  def request_all!(record, scopes)
    scopes.each { |scope| request_scope!(record, scope) }
  end

  def request_scope!(record, scope)
    requests = JrcApprovals::Requests.new(account: @account, user: @member.user).create!(
      key: JrcContactCenter::PauseApprovalPolicyCheck::KEY, resource_id: scope.id,
      idempotency_key: "cc-pause:#{record.request_id}:#{scope.id}"
    )
    raise JrcContactCenter::OperationError.new('pause_approval_policy_missing', status: :conflict) if requests.empty?
  end
end
