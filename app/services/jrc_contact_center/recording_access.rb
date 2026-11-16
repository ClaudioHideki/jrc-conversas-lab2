class JrcContactCenter::RecordingAccess
  def self.authorize!(account:, user:, action:)
    # The independent legacy softphone retains its own-extension contract.
    return unless account.feature_enabled?('jrc_contact_center')

    member = account.account_users.find_by!(user: user)
    policy = JrcContactCenter::ModulePolicy.new({ account: account, user: user, account_user: member }, :contact_center)
    raise Pundit::NotAuthorizedError unless policy.public_send("recordings_#{action}?")
  end
end
