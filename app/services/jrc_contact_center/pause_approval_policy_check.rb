# frozen_string_literal: true

# Mandatory pause policies never inherit a commercial shadow mode or an empty-policy approval.
# The source scope/review are proposed immutable evidence, not a second decision or pause engine.
class JrcContactCenter::PauseApprovalPolicyCheck
  KEY = 'contact_center.pause'

  def initialize(context:, lock: false)
    @lock = lock
    @account_id = context.fetch(:account).id
    @user_id = context.fetch(:user).id
    @member_id = context.fetch(:account_user).id
  end

  def call(scope_id:)
    refresh!
    scope = source_scope(scope_id)
    snapshot = JrcApprovals::Catalog.snapshot(account: @account, user: @user, key: KEY, resource_id: scope.id, purpose: :request)
    versions = selected_versions(snapshot)
    return { status: 'policy_missing', required: true, policy_version_ids: [], approved_policy_version_ids: [], requests: [] } if versions.empty?

    present(versions, requests(scope), snapshot)
  end

  private

  def selected_versions(snapshot)
    JrcApprovals::Selection.call(account: @account, key: KEY, snapshot: snapshot)
  rescue JrcApprovals::Error => e
    raise unless e.code == 'POLICY_REQUIRED'

    []
  end

  def refresh!
    @account = Account.find(@account_id)
    @user = User.find(@user_id)
    raise Pundit::NotAuthorizedError unless @account.active? && @user.active_for_authentication? && @account.feature_enabled?('jrc_approvals')

    @authorization = JrcApprovals::Authorization.new(account: @account, user: @user)
    @member = @authorization.member!
    raise Pundit::NotAuthorizedError unless @member.id == @member_id
  end

  def source_scope(identifier)
    identifier = JrcServiceDesk::Input.id(identifier)
    scope = JrcContactCenter::PauseApprovalScope.where(account: @account).find(identifier)
    review = scope.review
    valid = review.actor_account_user_id == @member.id && review.actor_user_id == @user.id
    raise Pundit::NotAuthorizedError unless valid

    @authorization.authorize!('request_create', company_id: scope.issuer_company_id, unit_id: scope.business_unit_id)
    scope
  rescue ArgumentError
    raise JrcContactCenter::OperationError, 'invalid_pause_approval_scope'
  end

  def requests(scope)
    relation = JrcApprovals::Request.where(account: @account, resource_type: 'JrcContactCenter::PauseApprovalScope', resource_id: scope.id,
                                           requester_id: @member.id, module_key: 'contact_center', event_key: 'pause').order(:id)
    (@lock ? relation.lock : relation).to_a
  end

  def present(versions, records, snapshot)
    approved = versions.select do |version|
      latest = records.reverse.find { |record| record.policy_version_id == version.id }
      JrcApprovals::RequestVerification.approved?(latest, version, snapshot)
    end
    { status: approved.length == versions.length ? 'ready' : 'approval_required', required: true,
      policy_version_ids: versions.map(&:id), approved_policy_version_ids: approved.map(&:id), requests: request_states(records) }
  end

  def request_states(records)
    records.map { |record| { id: record.id.to_s, state: record.state, policy_version_id: record.policy_version_id.to_s } }
  end
end
