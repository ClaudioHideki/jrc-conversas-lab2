# Not a second source-access engine: only narrows existing native scopes.
# If several configured portfolios disagree, deny instead of inferring a grant.
class JrcRelationship::LocalAccess
  KEY = 'portfolio_local_access'.freeze

  def self.account_rules(member)
    JrcRelationship::Configuration.find_by(account_id: member.account_id, scope_key: 'account')&.rules&.fetch(KEY, nil)
  end

  def self.account_allowed?(member, action)
    JrcRelationship::LocalRoleRules.allowed?(account_rules(member), user_id: member.user_id, action: action, owner_id: :metadata)
  end

  def self.assignment_allowed?(member, assignment, action, document_category: nil)
    return false unless assignment.account_id == member.account_id
    groups = JrcRelationship::PortfolioGroupAssignment.where(account_id: member.account_id, assignment_id: assignment.id, active: true)
    group_ids = JrcRelationship::PortfolioGroup.where(account_id: member.account_id, status: 'active', id: groups.select(:portfolio_group_id)).pluck(:id)
    keys = ['account'] + group_ids.map { |id| "portfolio:#{id}" }
    rules = JrcRelationship::Configuration.where(account_id: member.account_id, scope_key: keys).pluck(:rules).map { |row| row[KEY] }.compact
    teams = TeamMember.where(user_id: member.user_id, team_id: Team.where(account_id: member.account_id).select(:id)).pluck(:team_id)
    rules.all? do |rule|
      JrcRelationship::LocalRoleRules.allowed?(rule, user_id: member.user_id, action: action,
        owner_id: assignment.owner_id, team_id: assignment.team_id, actor_team_ids: teams, document_category: document_category)
    end
  end

  def self.authorize_assignment!(context, assignment, action, document_category: nil)
    member = AccountUser.find_by!(account_id: context.account.id, user_id: context.user.id)
    raise Pundit::NotAuthorizedError unless member.user.active_for_authentication? &&
      assignment_allowed?(member, assignment, action, document_category: document_category)
  end

  def self.group_allowed?(context, group, action)
    return false unless group.account_id == context.account.id
    scope_groups(context, JrcRelationship::PortfolioGroup.where(account_id: context.account.id, id: group.id), action).exists?(id: group.id)
  end

  def self.scope_groups(context, rows, action)
    member = context.member
    rules = JrcRelationship::Configuration.where(account_id: member.account_id)
      .where("jsonb_exists(rules, ?)", KEY)
    teams = TeamMember.where(user_id: member.user_id, team_id: context.account.teams.select(:id)).select(:team_id)
    rules.each do |configuration|
      rule = configuration.rules[KEY]
      next if rule.nil?
      JrcRelationship::LocalRoleRules.normalize!(rule)
      next unless rule['enabled']
      binding = JrcRelationship::LocalRoleRules.binding(rule, member.user_id)
      allowed = binding && JrcRelationship::LocalRoleRules.allowed?(rule, user_id: member.user_id,
        action: action, owner_id: :metadata)
      restricted = allowed ? restrict_group_scope(context, rows, rule.fetch('roles').fetch(binding['role'])['scope'], teams) : rows.none
      if configuration.scope_key == 'account'
        rows = rows.where(id: restricted.select(:id))
      elsif configuration.scope_key.match?(/\Aportfolio:[1-9][0-9]*\z/)
        group_id = configuration.scope_key.split(':').last.to_i
        denied = rows.where(id: group_id).where.not(id: restricted.select(:id))
        rows = rows.where.not(id: denied.select(:id))
      end
    end
    rows
  end

  def self.restrict_group_scope(context, rows, scope, teams)
    return rows unless %w[own team].include?(scope)
    assignments = JrcRelationship::Assignment.where(account_id: context.account.id, owner_id: context.user.id)
    if scope == 'team'
      assignments = assignments.or(JrcRelationship::Assignment.where(account_id: context.account.id, team_id: teams))
    end
    links = JrcRelationship::PortfolioGroupAssignment.where(account_id: context.account.id, active: true,
      assignment_id: assignments.select(:id)).select(:portfolio_group_id)
    owned = rows.where(owner_id: context.user.id).or(rows.where(id: links))
    scope == 'team' ? owned.or(rows.where(team_id: teams)) : owned
  end
  private_class_method :restrict_group_scope

  def self.scope_assignments(context_hash, rows, action: 'view')
    member = context_hash.fetch(:account_user)
    configs = JrcRelationship::Configuration.where(account_id: member.account_id).where("jsonb_exists(rules, ?)", KEY).to_a
    # A present malformed rule is not equivalent to an absent/disabled rule.
    # Validate before choosing active rules, so a damaged flag cannot broaden a read.
    configs.each do |config|
      rule = config.rules[KEY]
      JrcRelationship::LocalRoleRules.normalize!(rule) unless rule.nil?
    end
    active = configs.select { |config| config.rules[KEY] && config.rules[KEY]['enabled'] }
    return rows if active.empty?
    teams = TeamMember.where(user_id: member.user_id, team_id: Team.where(account_id: member.account_id).select(:id)).pluck(:team_id)
    active.each do |config|
      rule = config.rules.fetch(KEY)
      binding = JrcRelationship::LocalRoleRules.binding(rule, member.user_id)
      allowed = binding && JrcRelationship::LocalRoleRules.allowed?(rule, user_id: member.user_id, action: action, owner_id: :metadata)
      scope = binding && rule.fetch('roles').fetch(binding['role']).fetch('scope')
      subset = case scope
               when 'own' then rows.where(owner_id: member.user_id)
               when 'team' then rows.where(owner_id: member.user_id).or(rows.where(team_id: teams))
               else rows
               end
      subset = rows.none unless allowed
      if config.scope_key == 'account'
        rows = rows.where(id: subset.select(:id))
      elsif config.scope_key.match?(/\Aportfolio:[1-9][0-9]*\z/)
        group_id = config.scope_key.split(':').last.to_i
        next unless JrcRelationship::PortfolioGroup.exists?(account_id: member.account_id, id: group_id, status: 'active')
        links = JrcRelationship::PortfolioGroupAssignment.where(account_id: member.account_id, portfolio_group_id: group_id, active: true)
        rows = rows.where.not(id: links.where.not(assignment_id: subset.select(:id)).select(:assignment_id))
      end
    end
    rows
  end

  def self.signature(member)
    JrcRelationship::Configuration.where(account_id: member.account_id).where("rules -> ? IS NOT NULL AND rules -> ? <> 'null'::jsonb", KEY, KEY).order(:scope_key).pluck(:scope_key, :version)
  end

  def self.validate_references!(configuration)
    value = configuration.rules[KEY]
    return if value.nil?
    JrcRelationship::LocalRoleRules.normalize!(value)
    unless configuration.scope_key == 'account' || configuration.scope_key.match?(/\Aportfolio:[1-9][0-9]*\z/)
      raise ArgumentError, 'Local roles belong to account or named portfolio scope'
    end
    ids = value.fetch('members').map { |member| member.fetch('user_id') }
    raise ArgumentError, 'Local role users must belong to this account' unless
      AccountUser.where(account_id: configuration.account_id, user_id: ids).count == ids.length
  end
end
