class JrcProjects::Api::V1::SettingsController < JrcOperations::BaseController
  before_action :require_project_admin!
  def show
    render json: { data: {
      projects_enabled: true, administrator: true,
      agent_access: Current.account.account_users.includes(:user).map { |m| {
        account_user_id: m.id, name: m.user.name, role: m.role, enabled: m.jrc_projects_enabled?
      } }
    } }
  end
  def update
    values = params.require(:settings).permit(agent_access: [:account_user_id, :enabled]).to_h
    raise ArgumentError, 'Ativação é exclusiva do Super Admin.' if params[:settings].key?(:projects_enabled)
    JrcOperations::SettingsUpdater.call(account: Current.account, account_user: Current.account_user, values: values)
    show
  end
  private
  def require_project_admin!
    raise Pundit::NotAuthorizedError unless JrcOperations::Access.admin?(Current.account_user) &&
      JrcOperations::Access.enabled?(Current.account, 'projects')
  end
end
