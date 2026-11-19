module Enterprise::Api::V1::Accounts::TeamMembersController
  def self.prepended(base)
    base.rescue_from JrcContactCenter::TeamRosterWithdrawalReview::Required, with: :render_team_withdrawal_review
  end

  def create
    with_membership_authority_guard { super }
  end

  def update
    with_membership_authority_guard { super }
  end

  def destroy
    with_membership_authority_guard { super }
  end

  private

  def with_membership_authority_guard
    JrcContactCenter::AuthorityTransaction.call(account: Current.account, member: Current.account_user) do
      Current.user.reload
      raise Pundit::NotAuthorizedError unless Current.user.active_for_authentication?

      @team.reload
      check_authorization
      validate_member_id_params
      next if performed?

      validate_membership_activation unless action_name == 'destroy'
      review = team_withdrawal_review
      review.check!
      review.audit!
      yield
    end
  end

  def validate_membership_activation
    arguments = { account: Current.account, actor: Current.user, team: @team, user_ids: params[:user_ids] }
    JrcCrm::TeamScopeActivationGuard.check!(**arguments)
    JrcContactCenter::TeamAssignmentGuard.check!(**arguments) if Current.account.feature_enabled?('jrc_contact_center')
  end

  def team_withdrawal_review
    preview = JrcContactCenter::TeamRosterPreview.new(
      account: Current.account, actor: Current.account_user, team: @team, user_ids: params[:user_ids], operation: action_name
    )
    JrcContactCenter::TeamRosterWithdrawalReview.new(
      account: Current.account, actor: Current.account_user, preview: preview, confirmation: params[:manager_confirmation]
    )
  end

  def render_team_withdrawal_review(error)
    response.headers['Cache-Control'] = 'no-store'
    render json: { error: error.code, review: error.review }, status: error.status
  end
end
