module Enterprise::Api::V1::Accounts::AgentsController
  def create
    with_native_role_transaction do
      authorize_contact_center_role_assignment!
      super
      associate_agent_with_custom_role if @agent.present?
    end
  end

  def update
    with_native_role_transaction do
      authorize_contact_center_role_assignment!
      super
      associate_agent_with_custom_role
    end
  end

  private

  # The native bulk loop already holds the Account lock and deliberately
  # commits successful invitations before reporting rejected ones.
  def create_agent_from_email(email)
    Current.account_user.reload
    check_authorization
    member = AccountUser.new(account: Current.account, role: :agent)
    JrcContactCenter::RoleFallbackGuard.check!(actor: Current.user, account: Current.account, member: member)
    super
  end

  def role_change_requested?
    return true unless action_name == 'update'

    params.key?(:custom_role_id) || (params[:agent].respond_to?(:key?) && params[:agent].key?(:role))
  end

  def with_native_role_transaction
    return yield unless role_change_requested?

    JrcContactCenter::AuthorityTransaction.call(account: Current.account, member: Current.account_user) do
      check_authorization
      yield
    end
  end

  def requested_custom_role
    value = params[:custom_role_id]
    return if value.nil? || (value.is_a?(String) && value.strip.empty?)

    raise ActiveRecord::RecordNotFound unless custom_role_identifier?(value)

    Current.account.custom_roles.find(value)
  end

  def custom_role_identifier?(value)
    scalar = value.is_a?(Integer) || value.is_a?(String)
    scalar && value.to_s.match?(/\A[1-9]\d{0,18}\z/) && value.to_i <= 9_223_372_036_854_775_807
  end

  def authorize_contact_center_role_assignment!
    return if action_name == 'update' && !role_change_requested?

    member = @agent ? Current.account.account_users.find_by!(user_id: @agent.id) : AccountUser.new(account: Current.account)
    return if preserving_contact_center_profile?(member)

    check_contact_center_role_effect!(member, requested_custom_role)
  end

  def preserving_contact_center_profile?(member)
    action_name == 'update' && !params.key?(:custom_role_id) && member.custom_role_id.present?
  end

  def check_contact_center_role_effect!(member, role)
    if role
      JrcContactCenter::GrantGuard.check!(
        actor: Current.user, account: Current.account, proposed: role.permissions, previous: member.custom_role&.permissions || []
      )
      JrcContactCenter::RoleFallbackGuard.check!(actor: Current.user, account: Current.account, member: member, custom_role: role)
    else
      values = action_name == 'create' ? new_agent_params : agent_params
      proposed_role = values[:role].nil? ? member.role : values[:role]
      JrcContactCenter::RoleFallbackGuard.check!(actor: Current.user, account: Current.account, member: member, role: proposed_role)
    end
  end

  def associate_agent_with_custom_role
    return unless params.key?(:custom_role_id)

    @agent.current_account_user.update!(custom_role: requested_custom_role)
  end
end
