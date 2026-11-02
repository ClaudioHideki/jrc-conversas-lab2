class SuperAdmin::Api::Inboxes::AssignmentPoliciesController < SuperAdmin::Api::BaseController
  before_action :ensure_inbox!
  before_action :fetch_assignment_policy, only: [:create]
  before_action :validate_assignment_policy, only: [:show, :destroy]

  def show
    @assignment_policy = @inbox.assignment_policy
    render 'api/v1/accounts/inboxes/assignment_policies/show'
  end

  def create
    current_account.with_lock do
      remove_inbox_assignment_policy
      @inbox_assignment_policy = @inbox.create_inbox_assignment_policy!(
        assignment_policy: @assignment_policy
      )
      @assignment_policy = @inbox.assignment_policy
    end
    render 'api/v1/accounts/inboxes/assignment_policies/create'
  end

  def destroy
    current_account.with_lock { remove_inbox_assignment_policy }
    head :ok
  end

  private

  def fetch_assignment_policy
    @assignment_policy = current_account.assignment_policies.find(
      params[:assignment_policy_id]
    )
  end

  def remove_inbox_assignment_policy
    @inbox.inbox_assignment_policy&.destroy
  end

  def validate_assignment_policy
    return if @inbox.assignment_policy

    render_not_found_error(I18n.t('errors.assignment_policy.not_found'))
  end
end
