# Rejoining a team can reactivate an existing corporate source without editing it.
class JrcCrm::TeamScopeActivationGuard
  def self.check!(account:, actor:, team:, user_ids:)
    added = user_ids.map(&:to_i).uniq - team.team_members.pluck(:user_id)
    sources = account.jrc_crm_user_business_units.structure_managed.active.where(team_id: team.id, user_id: added)
    return unless sources.exists?

    coverage = JrcCrm::CorporateCoverage.new(account: account, user: actor)
    return if account.account_users.exists?(user_id: actor.id, role: :administrator) && coverage.group?

    raise Pundit::NotAuthorizedError
  end
end
