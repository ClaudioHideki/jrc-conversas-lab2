class Api::V1::Accounts::CustomRolesController < Api::V1::Accounts::EnterpriseAccountsController
  before_action :fetch_custom_role, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @custom_roles = Current.account.custom_roles
  end

  def show; end

  def create
    @custom_role = Current.account.custom_roles.create!(permitted_params)
  end

  def update
    # Reload under the native row lock before computing newly granted powers.
    @custom_role.with_lock { @custom_role.update!(permitted_params) }
  end

  def destroy
    @custom_role.with_lock do
      check_contact_center_role_scope!(@custom_role.permissions)
      @custom_role.destroy!
    end
    head :ok
  end

  def permitted_params
    attributes = params.require(:custom_role).permit(:name, :description, permissions: [])
    check_contact_center_role_scope!(attributes.fetch(:permissions, @custom_role&.permissions || []))
    if attributes.key?(:permissions)
      JrcContactCenter::GrantGuard.check!(
        actor: Current.user, account: Current.account, proposed: attributes[:permissions], previous: @custom_role&.permissions || []
      )
    end
    attributes
  end

  def check_contact_center_role_scope!(proposed)
    capabilities = Array(proposed) | Array(@custom_role&.permissions)
    return unless capabilities.intersect?(JrcContactCenter::ModulePolicy::PERMISSIONS)

    coverage = JrcCrm::CorporateCoverage.new(account: Current.account, user: Current.user)
    raise Pundit::NotAuthorizedError if coverage.configured? && !coverage.group?
  end

  def fetch_custom_role
    @custom_role = Current.account.custom_roles.find(params[:id])
  end
end
