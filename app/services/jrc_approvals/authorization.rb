class JrcApprovals::Authorization
  PERMISSIONS = %w[policy_manage request_create decide view_audit].map { |name| "jrc_approvals_#{name}" }.freeze

  def self.scope!(account, company_id, unit_id)
    raise JrcApprovals::Error, 'INVALID_SCOPE' if unit_id && !company_id
    return unless company_id

    company = JrcCustomers::Company.where(account_id: account.id, relationship_type: 'internal', active: true).find(company_id)
    return company unless unit_id

    JrcCrm::BusinessUnit.where(account_id: account.id, company_id: company.id, active: true).find(unit_id)
  end

  def initialize(account:, user:)
    @account, @user = account, user
  end

  def member!
    member = @account.account_users.includes(:user).find_by(user_id: @user&.id)
    raise Pundit::NotAuthorizedError unless @account.active? && @account.feature_enabled?('jrc_approvals') &&
      member && member.user.active_for_authentication?

    member
  end

  def authorize!(action, company_id:, unit_id:)
    member = member!
    self.class.scope!(@account, company_id, unit_id)
    permission = "jrc_approvals_#{action}"
    explicit = member.permissions.include?(permission)
    native_management = member.administrator? && member.custom_role_id.nil? && action != 'decide'
    raise Pundit::NotAuthorizedError unless (explicit || native_management) && covered?(company_id, unit_id)

    member
  end

  def covered?(company_id, unit_id)
    JrcCrm::UserBusinessUnit.structure_managed.active.where(account_id: @account.id, user_id: @user.id).any? do |scope|
      scope.scope == 'GROUP' || (scope.scope == 'COMPANY' && company_id && scope.company_id == company_id) ||
        (scope.scope == 'BUSINESS_UNIT' && unit_id && scope.business_unit_id == unit_id)
    end
  end
end
