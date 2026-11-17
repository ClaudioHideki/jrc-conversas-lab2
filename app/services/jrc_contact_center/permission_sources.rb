class JrcContactCenter::PermissionSources
  UNSPECIFIED = Object.new.freeze

  def initialize(account:, member:, individual: UNSPECIFIED, team_overrides: {}, extra_permissions: [])
    @account = account
    @member = member
    @preview = individual
    @team_overrides = team_overrides
    @extra_permissions = extra_permissions
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
    @inherited_permissions ||= begin
      grants = JrcContactCenter::AccessGrant.where(account: @account, team_id: teams.select(:id)).pluck(:team_id, :allowed).to_h
      @team_overrides.each { |id, permissions| grants[id] = permissions if teams.exists?(id: id) }
      (grants.values.flatten + @extra_permissions).uniq
    end
  end

  def origins
    grants = JrcContactCenter::AccessGrant.where(account: @account, team_id: teams.select(:id)).includes(:team).order(:team_id)
    role = @member.custom_role
    {
      profile: role&.account_id == @account.id ? { id: role.id, name: role.name, permissions: profile } : nil,
      teams: grants.filter_map do |grant|
        next if grant.allowed.empty?

        { id: grant.team_id, name: grant.team.name, permissions: grant.allowed }
      end
    }
  end
end
