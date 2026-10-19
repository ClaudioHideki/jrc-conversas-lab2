class JrcRelationship::BatchReviewAuthority
  LOCK = 'FOR SHARE NOWAIT'.freeze

  def initialize(account_id:, actor_id:)
    @account_id = account_id
    @actor_id = actor_id
  end

  def call
    ActiveRecord::Base.uncached do
      context = JrcRelationship::Context.new(lock_member)
      raise Pundit::NotAuthorizedError unless context.policy.manage?

      yield context
    end
  end

  private

  def lock_member
    Account.lock(LOCK).find(@account_id)
    user = User.lock(LOCK).find(@actor_id)
    member = AccountUser.lock(LOCK).find_by!(account_id: @account_id, user_id: @actor_id)
    CustomRole.lock(LOCK).find(member.custom_role_id) if member.custom_role_id
    lock_grants(member)
    raise Pundit::NotAuthorizedError unless user.active_for_authentication?

    member
  end

  def lock_grants(member)
    TeamMember.where(user_id: @actor_id, team_id: Team.where(account_id: @account_id).select(:id)).order(:id).lock(LOCK).load
    JrcCrm::UserBusinessUnit.where(account_id: @account_id, user_id: @actor_id).order(:id).lock(LOCK).load
    InboxMember.where(user_id: @actor_id, inbox_id: Inbox.where(account_id: @account_id).select(:id)).order(:id).lock(LOCK).load
    JrcServiceDesk::UnitMembership.where(account_id: @account_id, account_user_id: member.id).order(:id).lock(LOCK).load
    JrcProjects::ProjectMember.where(account_id: @account_id, user_id: @actor_id).order(:id).lock(LOCK).load
  end
end
