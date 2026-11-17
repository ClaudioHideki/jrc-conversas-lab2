class JrcContactCenter::PermissionSources
  UNSPECIFIED = Object.new.freeze

  def initialize(account:, member:, individual: UNSPECIFIED)
    @account = account
    @member = member
    @preview = individual
  end

  def individual
    return unless @member&.id && @member.account_id == @account.id
    return @preview unless @preview.equal?(UNSPECIFIED)

    @individual ||= JrcContactCenter::AccessGrant.find_by(account: @account, account_user_id: @member.id)
  end

  def eligible?
    individual&.eligible? == true
  end

  def denied?(permission)
    Array(individual&.denied).include?(permission)
  end

  def granted?(permission)
    (profile + Array(individual&.allowed) + inherited_permissions).include?(permission)
  end

  def profile
    role = @member.custom_role
    role&.account_id == @account.id ? role.permissions & JrcContactCenter::ModulePolicy::PERMISSIONS : []
  end

  def teams
    Team.where(account: @account).joins(:team_members).where(team_members: { user_id: @member.user_id }).distinct
  end

  def inherited_permissions
    @inherited_permissions ||= JrcContactCenter::AccessGrant.where(account: @account, team_id: teams.select(:id)).pluck(:allowed).flatten.uniq
  end
end
