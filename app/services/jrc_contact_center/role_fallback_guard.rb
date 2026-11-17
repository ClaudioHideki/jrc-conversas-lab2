class JrcContactCenter::RoleFallbackGuard
  def self.check!(actor:, account:, member:, role: member.role)
    raise Pundit::NotAuthorizedError unless member.account_id == account.id

    previous = member.new_record? ? [] : permissions(account, member)
    proposed = fallback_permissions(account, member, role)
    JrcContactCenter::GrantGuard.check!(actor: actor, account: account, proposed: proposed, previous: previous)
  end

  def self.check_destroy!(actor:, account:, role:)
    raise Pundit::NotAuthorizedError if role.account_users.where.not(account_id: account.id).exists?

    added = []
    role.account_users.includes(:user, :custom_role).find_each do |member|
      added |= fallback_permissions(account, member, member.role) - permissions(account, member)
    end
    JrcContactCenter::GrantGuard.check!(actor: actor, account: account, proposed: added)
  end

  def self.fallback_permissions(account, member, role)
    proposed = member.dup
    proposed.id = member.id
    proposed.custom_role = nil
    proposed.role = role
    proposed.readonly!
    permissions(account, proposed)
  end

  def self.permissions(account, member)
    return [] if member.custom_role && member.custom_role.account_id != account.id

    context = { account: account, account_user: member, user: member.user }
    JrcContactCenter::ModulePolicy.new(context, :contact_center).effective_permissions
  end
  private_class_method :fallback_permissions, :permissions
end
