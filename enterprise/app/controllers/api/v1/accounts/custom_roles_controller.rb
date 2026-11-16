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
    @custom_role.destroy!
    head :ok
  end

  def permitted_params
    attributes = params.require(:custom_role).permit(:name, :description, permissions: [])
    if attributes.key?(:permissions)
      JrcContactCenter::GrantGuard.check!(
        actor: Current.user, account: Current.account, proposed: attributes[:permissions], previous: @custom_role&.permissions || []
      )
    end
    attributes
  end

  def fetch_custom_role
    @custom_role = Current.account.custom_roles.find(params[:id])
  end
end
