# frozen_string_literal: true

# Validate restored rights and coverage before persisting a team source change.
class JrcContactCenter::TeamGrantEffects
  def initialize(authority:, team:, grant:, previous:, activity:)
    @account = authority.account
    @actor = authority.user
    @authority = authority
    @team = team
    @grant = grant
    @previous = previous
    @activity = activity
  end

  def check!
    previous = @activity[@team.id] == true ? [] : @previous
    JrcContactCenter::GrantGuard.check!(actor: @actor, account: @account, proposed: @grant.allowed, previous: previous)
    @account.account_users.where(user_id: @team.team_members.select(:user_id)).includes(:user).find_each do |member|
      proposed = @authority.effective(member, team_preview: { @team.id => @grant.allowed }, activity: @activity)
      previous = expanded_coverage?(member.user) ? [] : @authority.effective(member)
      JrcContactCenter::GrantGuard.check!(actor: @actor, account: @account, proposed: proposed, previous: previous)
    end
  end

  private

  def expanded_coverage?(user)
    return false if @activity.empty?

    previous = JrcContactCenter::CorporateCoverage.new(account: @account, user: user)
    proposed = JrcContactCenter::CorporateCoverage.new(account: @account, user: user, team_activity_preview: @activity)
    return false unless previous.configured?
    return true if proposed.group? && !previous.group?

    proposed.unit_ids.where.not(id: previous.unit_ids).exists? || proposed.company_ids.where.not(id: previous.company_ids).exists?
  end
end
