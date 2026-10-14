class JrcOperator::Access
  CAPABILITIES = %w[read reserve release prepare_boleto send_boleto].freeze
  PERMISSIONS = CAPABILITIES.map { |key| "jrc_operator_#{key}" }.freeze
  def initialize(account:, user:)
    @account = account
    @user = user
  end

  def member!
    raise Pundit::NotAuthorizedError unless @user.is_a?(::User)

    member = @account.account_users.includes(:user).find_by(user_id: @user.id)
    allowed = @account.active? && @account.feature_enabled?('jrc_operator') && member&.user&.active_for_authentication?
    raise Pundit::NotAuthorizedError unless allowed

    member
  end

  def authorize!(capability)
    raise Pundit::NotAuthorizedError unless CAPABILITIES.include?(capability) && member!.permissions.include?("jrc_operator_#{capability}")
  end

  def bindings
    authorize!('read')
    scopes = JrcCrm::UserBusinessUnit.structure_managed.active.where(account_id: @account.id, user_id: @user.id)
    units = JrcCrm::BusinessUnit.active.where(account_id: @account.id)
    unless scopes.exists?(scope: 'GROUP')
      direct = scopes.where(scope: 'BUSINESS_UNIT').pluck(:business_unit_id)
      companies = scopes.where(scope: 'COMPANY').pluck(:company_id)
      units = units.where(id: direct).or(units.where(company_id: companies))
    end
    JrcOperator::Binding.where(account_id: @account.id, active: true, business_unit_id: units.select(:id))
  end

  def binding!(id, capability = 'read')
    authorize!(capability)
    binding = bindings.includes(:contact, :company, :business_unit).find(id)
    raise Pundit::NotAuthorizedError unless ContactPolicy.new({ account: @account, user: @user, account_user: member! }, binding.contact).show?
    raise Pundit::NotAuthorizedError unless binding.valid?

    binding
  end
end
