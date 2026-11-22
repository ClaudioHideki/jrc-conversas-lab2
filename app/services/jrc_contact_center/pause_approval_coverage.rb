# frozen_string_literal: true

# Internal evidence only. Never accepts client unit/user IDs and never grants, requests or applies an approval.
# A pause is native account-user state, so a selected queue cannot narrow its affected operational units.
class JrcContactCenter::PauseApprovalCoverage
  def initialize(context:)
    @account_id = context.fetch(:account).id
    @member_id = context.fetch(:account_user).id
    @user_id = context.fetch(:user).id
  end

  def call
    refresh!
    rows = JrcContactCenter::AgentStateSnapshot.new(account_user: @member).memberships.includes(queue: :unit).order(:id).to_a
    raise JrcContactCenter::OperationError, 'pause_approval_scope_missing' if rows.empty?

    values = capture(rows)
    values.merge('digest' => JrcApprovals::Ledger.digest(values))
  end

  private

  def capture(rows)
    units = rows.map { |row| row.queue.unit }.uniq(&:id).sort_by(&:id).map { |unit| unit_snapshot(unit) }
    { 'account_id' => @account.id.to_s, 'actor_account_user_id' => @member.id.to_s,
      'actor_user_id' => @member.user_id.to_s, 'actor_authority' => actor_authority,
      'units' => units, 'groups' => groups(units), 'memberships' => rows.map { |row| membership_snapshot(row) },
      'all_affected_units' => true, 'local_only' => true, 'provider_confirmed' => false }
  end

  def refresh!
    @account = Account.find(@account_id)
    @member = @account.account_users.includes(:user, :custom_role).find(@member_id)
    @user = User.find(@user_id)
    context = { account: @account, account_user: @member, user: @user }
    @policy = JrcContactCenter::ModulePolicy.new(context, :contact_center)
    raise Pundit::NotAuthorizedError unless @account.active? && @user.active_for_authentication? && @policy.operate?
  end

  def actor_authority
    eligible = JrcContactCenter::PermissionSources.new(account: @account, member: @member).eligible?
    { 'role' => @member.role, 'custom_role_id' => @member.custom_role_id&.to_s,
      'contact_center_eligible' => eligible, 'effective_permissions' => @policy.effective_permissions.sort }
  end

  def unit_snapshot(unit)
    scope = JrcContactCenter::ConfigurationAuditSnapshot.capture(unit).fetch('scope')
    raise JrcContactCenter::OperationError, 'pause_approval_scope_missing' if scope['issuer_company_id'].blank?

    JrcApprovals::Authorization.scope!(@account, scope['issuer_company_id'], scope['business_unit_id'])
    { 'id' => unit.id.to_s, 'name' => unit.name, 'status' => unit.status, 'scope' => scope }
  end

  def groups(units)
    units.group_by { |row| row.fetch('scope').values_at('issuer_company_id', 'business_unit_id') }.map do |(company, business), rows|
      { 'issuer_company_id' => company, 'business_unit_id' => business, 'unit_ids' => rows.map { |row| row.fetch('id') } }
    end
  end

  def membership_snapshot(row)
    queue = row.queue
    { 'id' => row.id.to_s, 'queue_id' => queue.id.to_s, 'unit_id' => queue.unit_id.to_s,
      'role' => row.role, 'active' => row.active, 'starts_at' => row.starts_at&.iso8601(6), 'ends_at' => row.ends_at&.iso8601(6),
      'queue_status' => queue.status, 'queue_active_from' => queue.active_from&.iso8601(6), 'queue_active_until' => queue.active_until&.iso8601(6) }
  end
end
