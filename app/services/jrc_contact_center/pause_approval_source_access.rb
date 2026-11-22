# frozen_string_literal: true

# Native source access is independent of Central decision authority; both checks remain necessary.
class JrcContactCenter::PauseApprovalSourceAccess
  def self.allowed?(scope, actor)
    new(scope, actor).allowed?
  rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError, JrcApprovals::Error
    false
  end

  def initialize(scope, actor)
    @scope = scope
    @account = Account.find(scope.account_id)
    @actor = User.find(actor&.id)
    @member = @account.account_users.find_by!(user_id: @actor.id)
  end

  def allowed?
    return false unless active_actor? && native_allowed?

    JrcApprovals::Authorization.scope!(@account, @scope.issuer_company_id, @scope.business_unit_id)
    authorization = JrcApprovals::Authorization.new(account: @account, user: @actor)
    authorization.covered?(@scope.issuer_company_id, @scope.business_unit_id) && units_covered?
  end

  private

  def active_actor?
    @account.active? && @actor.active_for_authentication? && @account.feature_enabled?('jrc_approvals')
  end

  def native_allowed?
    context = { account: @account, account_user: @member, user: @actor }
    policy = JrcContactCenter::ModulePolicy.new(context, :contact_center)
    owner = @scope.review.actor_user_id == @actor.id && @scope.review.actor_account_user_id == @member.id
    owner ? policy.operate? : policy.approve?
  end

  def units_covered?
    ids = @scope.unit_ids
    return false unless ids.is_a?(Array) && ids.any? && ids.uniq == ids

    units = JrcContactCenter::OrganizationalScope.new(account: @account, account_user: @member).units.where(id: ids).to_a
    units.size == ids.size && units.all? { |unit| native_scope?(unit) }
  end

  def native_scope?(unit)
    unit.status == 'active' && unit.settings['issuer_company_id'].to_s == @scope.issuer_company_id.to_s &&
      unit.settings['business_unit_id'].presence&.to_s == @scope.business_unit_id&.to_s
  end
end
