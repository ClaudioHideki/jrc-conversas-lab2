class JrcContactCenter::GrantGuard
  def self.check!(actor:, account:, proposed:, previous: [])
    added = (Array(proposed) - Array(previous)) & JrcContactCenter::ModulePolicy::PERMISSIONS
    return if added.empty? || actor.is_a?(SuperAdmin)

    member = account.account_users.find_by!(user_id: actor.id)
    coverage = JrcCrm::CorporateCoverage.new(account: account, user: actor)
    raise Pundit::NotAuthorizedError if coverage.configured? && !coverage.group?

    policy = JrcContactCenter::ModulePolicy.new({ account: account, account_user: member, user: actor }, :contact_center)
    allowed = added.all? do |permission|
      action = permission.delete_prefix('jrc_contact_center_')
      policy.public_send("#{action == 'view' ? 'access' : action}?")
    end
    raise Pundit::NotAuthorizedError unless allowed
  end
end
