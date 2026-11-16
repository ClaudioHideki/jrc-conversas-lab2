module Enterprise::Api::V1::Accounts::AgentsController
  def create
    authorize_contact_center_role_assignment!
    super
    return if @agent.blank?

    associate_agent_with_custom_role
  end

  def update
    authorize_contact_center_role_assignment!
    super
    associate_agent_with_custom_role
  end

  private

  def authorize_contact_center_role_assignment!
    return if params[:custom_role_id].blank?

    role = Current.account.custom_roles.find(params[:custom_role_id])
    previous = @agent&.account_users&.find_by(account_id: Current.account.id)&.custom_role&.permissions || []
    JrcContactCenter::GrantGuard.check!(actor: Current.user, account: Current.account, proposed: role.permissions, previous: previous)
  end

  def associate_agent_with_custom_role
    @agent.current_account_user.update!(custom_role_id: params[:custom_role_id])
  end
end
