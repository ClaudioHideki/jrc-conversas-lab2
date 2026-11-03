module JrcMigrations::Access
  def self.authorize!(account, user, lock: false)
    raise JrcMigrations::Error, 'MIGRATION_FORBIDDEN' unless user.is_a?(User)

    scope = AccountUser.where(account_id: account.id, user_id: user&.id, role: :administrator)
    scope = scope.lock if lock
    raise JrcMigrations::Error, 'MIGRATION_FORBIDDEN' unless scope.first
  end
end
