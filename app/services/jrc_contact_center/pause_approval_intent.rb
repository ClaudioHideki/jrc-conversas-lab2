# frozen_string_literal: true

# Read-only preflight for a canonical native pause intent. Never supplies grants or applies a pause.
# State/revision concurrency stays with DeferredPauseManager, outside the historical input digest.
class JrcContactCenter::PauseApprovalIntent
  def initialize(context:)
    @account_id = context.fetch(:account).id
    @member_id = context.fetch(:account_user).id
    @user_id = context.fetch(:user).id
  end

  def call(attributes)
    refresh!
    values = JrcContactCenter::DeferredPauseInput.call(attributes)
    selection = JrcContactCenter::DeferredPauseSelection.new(account: @account, member: @member).call(values)
    return { 'required' => false, 'selection' => selection.stringify_keys } unless mandatory?(values)

    coverage = JrcContactCenter::PauseApprovalCoverage.new(context: context).call
    authorize_all_scopes!(coverage)
    payload = { 'version' => 1, 'request_id' => values.fetch(:command_id),
                'intent' => values.slice(:reason_code, :queue_id, :justification).stringify_keys,
                'selection' => selection.stringify_keys, 'coverage' => coverage }
    { 'required' => true, 'payload' => payload, 'digest' => JrcApprovals::Ledger.digest(payload),
      'local_only' => true, 'provider_confirmed' => false }
  end

  private

  def refresh!
    @account = Account.find(@account_id)
    @member = @account.account_users.find(@member_id)
    @user = User.find(@user_id)
    policy = JrcContactCenter::ModulePolicy.new(context, :contact_center)
    raise Pundit::NotAuthorizedError unless @account.active? && @user.active_for_authentication? && policy.operate?
  end

  def context
    { account: @account, account_user: @member, user: @user }
  end

  def mandatory?(values)
    catalog = JrcContactCenter::PauseCatalog.new(account: @account)
    memberships = JrcContactCenter::AgentStateSnapshot.new(account_user: @member).memberships
    memberships = memberships.where(queue_id: values[:queue_id]) if values[:queue_id]
    definition = catalog.selection(values.fetch(:reason_code), member: @member, memberships: memberships)
    catalog.enforced? && definition&.fetch('approval_required', false) == true
  end

  def authorize_all_scopes!(coverage)
    authorization = JrcApprovals::Authorization.new(account: @account, user: @user)
    coverage.fetch('groups').each do |group|
      authorization.authorize!('request_create', company_id: group.fetch('issuer_company_id')&.to_i,
                               unit_id: group.fetch('business_unit_id')&.to_i)
    end
  end
end
