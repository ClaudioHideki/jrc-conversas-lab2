# Local roles narrow native group metadata; they never expose hidden customers.
class JrcRelationship::PortfolioGroupScope
  def self.resolve(context)
    rows = organizational(context)
    unless context.policy.admin?
      teams = TeamMember.where(user_id: context.user.id, team_id: context.account.teams.select(:id)).select(:team_id)
      rows = rows.where(owner_id: context.user.id).or(rows.where(visibility: 'account')).or(rows.where(visibility: 'team', team_id: teams))
    end
    JrcRelationship::LocalAccess.scope_groups(context, rows, 'view')
  end

  def self.organizational(context)
    raise Pundit::NotAuthorizedError unless context.user.active_for_authentication? && context.policy.access?
    rows = JrcRelationship::PortfolioGroup.where(account_id: context.account.id)
    JrcCrm::OrganizationalVisibility.new(account: context.account, user: context.user, relation: rows, include_company: false).call
  end

  def self.writable(context)
    rows = resolve(context)
    return rows.none unless context.policy.manage? && context.policy.team?
    unless context.policy.admin?
      teams = TeamMember.where(user_id: context.user.id, team_id: context.account.teams.select(:id)).select(:team_id)
      rows = rows.where(owner_id: context.user.id).or(rows.where(team_id: teams))
    end
    JrcRelationship::LocalAccess.scope_groups(context, rows, 'manage_portfolios')
  end
end
