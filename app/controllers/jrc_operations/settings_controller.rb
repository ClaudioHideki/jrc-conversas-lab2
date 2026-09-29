class JrcOperations::SettingsController < JrcOperations::BaseController
  def show
    render json: { data: {
      ready: JrcOperations::Access.ready?, time_zone: Time.zone.tzinfo.name,
      administrator: JrcOperations::Access.admin?(Current.account_user),
      service_desk_enabled: JrcServiceDesk::ModulePolicy.new(JrcOperations::Access.r2_context(Current.account_user), Current.account).show?,
      projects_enabled: JrcOperations::Access.project_access?(Current.account_user),
      crm_enabled: JrcOperations::Access.crm?(Current.account_user),
      can_create_project: JrcOperations::Access.project_creator?(Current.account_user)
    } }
  end
  def update
    raise Pundit::NotAuthorizedError
  end
end
