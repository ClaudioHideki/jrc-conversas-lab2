class Api::V1::Accounts::CustomRolesController < Api::V1::Accounts::EnterpriseAccountsController
  before_action :fetch_custom_role, only: [:show, :update, :destroy]
  before_action :check_authorization
  rescue_from JrcContactCenter::OperationError, with: :render_contact_center_role_error

  def index
    @custom_roles = Current.account.custom_roles
  end

  def show; end

  def create
    with_contact_center_role_transaction do
      @custom_role = Current.account.custom_roles.create!(permitted_params)
    end
  end

  def update
    with_contact_center_role_transaction do
      @custom_role.with_lock do
        attributes = permitted_params
        JrcContactCenter::RoleRevision.check!(@custom_role, params[:expected_revision]) if params.key?(:expected_revision)
        @custom_role.update!(attributes)
      end
    end
  end

  def destroy
    with_contact_center_role_transaction do
      @custom_role.with_lock do
        check_contact_center_role_scope!(@custom_role.permissions)
        JrcContactCenter::RoleFallbackGuard.check_destroy!(actor: Current.user, account: Current.account, role: @custom_role)
        @custom_role.destroy!
      end
    end
    head :ok
  end

  def with_contact_center_role_transaction
    JrcContactCenter::AuthorityTransaction.call(account: Current.account, member: Current.account_user) do
      check_authorization
      yield
    end
  end
  private :with_contact_center_role_transaction

  def permitted_params
    attributes = params.require(:custom_role).permit(:name, :description, permissions: [])
    check_contact_center_role_scope!(attributes.fetch(:permissions, @custom_role&.permissions || []))
    if attributes.key?(:permissions)
      JrcContactCenter::GrantGuard.check!(
        actor: Current.user, account: Current.account, proposed: attributes[:permissions], previous: @custom_role&.permissions || []
      )
      check_assigned_role_effect!(attributes[:permissions]) if @custom_role
    end
    attributes
  end

  def check_assigned_role_effect!(permissions)
    proposed = @custom_role.dup
    proposed.id = @custom_role.id
    proposed.permissions = permissions
    proposed.readonly!
    @custom_role.account_users.includes(:user, :custom_role).find_each do |member|
      JrcContactCenter::RoleFallbackGuard.check!(actor: Current.user, account: Current.account, member: member, custom_role: proposed)
    end
  end

  def check_contact_center_role_scope!(proposed)
    capabilities = Array(proposed) | Array(@custom_role&.permissions)
    return unless capabilities.intersect?(JrcContactCenter::ModulePolicy::PERMISSIONS)

    coverage = JrcCrm::CorporateCoverage.new(account: Current.account, user: Current.user)
    raise Pundit::NotAuthorizedError if coverage.configured? && !coverage.group?
  end

  def render_contact_center_role_error(error)
    render json: { error: error.code }, status: error.status
  end

  def fetch_custom_role
    @custom_role = Current.account.custom_roles.find(params[:id])
  end
end
