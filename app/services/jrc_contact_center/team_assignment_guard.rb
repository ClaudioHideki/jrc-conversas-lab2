class JrcContactCenter::TeamAssignmentGuard
  def self.check!(account:, actor:, team:, user_ids:)
    return unless JrcContactCenter::TeamState.source_active?(account: account, team_id: team.id)

    capabilities = JrcContactCenter::AccessGrant.find_by(account: account, team: team)&.allowed || []
    return if capabilities.empty?

    added = user_ids.map(&:to_i).uniq - team.team_members.pluck(:user_id)
    account.account_users.where(user_id: added).find_each do |member|
      context = { account: account, account_user: member, user: member.user }
      previous = JrcContactCenter::ModulePolicy.new(context, :contact_center).effective_permissions
      JrcContactCenter::GrantGuard.check!(actor: actor, account: account, proposed: capabilities, previous: previous)
      context[:cc_extra_team_permissions] = capabilities
      proposed = JrcContactCenter::ModulePolicy.new(context, :contact_center).effective_permissions
      JrcContactCenter::GrantGuard.check!(actor: actor, account: account, proposed: proposed, previous: previous)
    end
  end
end
