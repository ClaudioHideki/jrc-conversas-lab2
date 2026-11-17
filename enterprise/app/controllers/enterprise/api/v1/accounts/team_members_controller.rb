module Enterprise::Api::V1::Accounts::TeamMembersController
  def create
    with_contact_center_membership_guard { super }
  end

  def update
    with_contact_center_membership_guard { super }
  end

  def destroy
    with_contact_center_membership_guard { super }
  end

  private

  def with_contact_center_membership_guard
    return yield unless Current.account.feature_enabled?('jrc_contact_center')

    JrcContactCenter::AuthorityTransaction.call(account: Current.account, member: Current.account_user) do
      @team.reload
      check_authorization
      validate_member_id_params
      next if performed?

      JrcContactCenter::TeamAssignmentGuard.check!(account: Current.account, actor: Current.user, team: @team, user_ids: params[:user_ids])
      yield
    end
  end
end
