# Normalize only Call Center authorities after the native/Enterprise permission chain.
module JrcContactCenter::AccountUserPermissions
  def permissions
    native_permissions = super - JrcContactCenter::ModulePolicy::PERMISSIONS
    return native_permissions unless account.feature_enabled?('jrc_contact_center')

    context = { account: account, account_user: self, user: user }
    native_permissions + JrcContactCenter::ModulePolicy.new(context, :contact_center).effective_permissions
  end
end
