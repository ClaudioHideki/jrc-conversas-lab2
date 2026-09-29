class JrcOperations::SettingsUpdater
  def self.call(account:, account_user:, values:)
    member = JrcOperations::Access.refresh(account_user)
    raise Pundit::NotAuthorizedError unless member && member.account_id == account.id && JrcOperations::Access.admin?(member)
    raise Pundit::NotAuthorizedError unless account.reload.feature_enabled?('jrc_projects')
    attrs = values.to_h.stringify_keys
    raise ArgumentError, 'A ativação do módulo pertence ao Super Admin.' unless (attrs.keys - ['agent_access']).empty?
    account.with_lock do
      Array(attrs['agent_access']).each do |grant|
        item = grant.to_h.stringify_keys
        target = account.account_users.find(item.fetch('account_user_id'))
        enabled = item.fetch('enabled')
        raise ArgumentError, 'Permissão deve ser true ou false.' unless [true, false].include?(enabled)
        before = target.jrc_projects_enabled
        target.update!(jrc_projects_enabled: enabled)
        JrcProjects::AuditEvent.record!(account: account, actor: member.user, action: 'projects.access.changed',
          auditable: target, before_data: { enabled: before }, after_data: { enabled: enabled })
      end
    end
  end
end
