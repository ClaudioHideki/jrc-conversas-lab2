module Enterprise::Api::V1::Accounts::TeamsController
  def self.prepended(base)
    base.rescue_from JrcContactCenter::TeamDeletionReview::Required, with: :render_team_deletion_review
  end

  def destroy
    JrcContactCenter::AuthorityTransaction.call(account: Current.account, member: Current.account_user) do
      Current.user.reload
      raise Pundit::NotAuthorizedError unless Current.user.active_for_authentication?

      @team = Current.account.teams.lock.find(params[:id])
      check_authorization
      review = team_deletion_review
      review.check!
      review.audit!
      super
    end
  rescue ActiveRecord::InvalidForeignKey, ActiveRecord::RecordNotDestroyed
    render json: { error: 'team_in_use' }, status: :conflict
  end

  private

  def team_deletion_review
    preview = JrcContactCenter::TeamRosterPreview.new(
      account: Current.account, actor: Current.account_user, team: @team, user_ids: [], operation: 'delete_team'
    )
    JrcContactCenter::TeamDeletionReview.new(
      account: Current.account, actor: Current.account_user, preview: preview, confirmation: params[:manager_confirmation]
    )
  end

  def render_team_deletion_review(error)
    response.headers['Cache-Control'] = 'no-store'
    render json: { error: error.code, review: error.review }, status: error.status
  end
end
