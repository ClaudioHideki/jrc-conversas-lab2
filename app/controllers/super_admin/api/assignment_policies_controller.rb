class SuperAdmin::Api::AssignmentPoliciesController < SuperAdmin::Api::BaseController
  before_action :fetch_assignment_policy, only: [:show, :update, :destroy]

  def index
    @assignment_policies = current_account.assignment_policies
    render 'api/v1/accounts/assignment_policies/index'
  end

  def show
    render 'api/v1/accounts/assignment_policies/show'
  end

  def create
    @assignment_policy = current_account.assignment_policies.create!(assignment_policy_params)
    render 'api/v1/accounts/assignment_policies/create'
  end

  def update
    current_account.with_lock { @assignment_policy.update!(assignment_policy_params) }
    render 'api/v1/accounts/assignment_policies/update'
  end

  def destroy
    current_account.with_lock { @assignment_policy.destroy! }
    head :ok
  end

  private

  def fetch_assignment_policy
    @assignment_policy = current_account.assignment_policies.find(params[:id])
  end

  def assignment_policy_params
    params.require(:assignment_policy).permit(
      :name, :description, :assignment_order, :conversation_priority,
      :fair_distribution_limit, :fair_distribution_window, :enabled,
      :exclude_older_than_hours
    )
  end
end
