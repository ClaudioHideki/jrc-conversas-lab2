class JrcCustomers::DirectoryPolicy < ApplicationPolicy
  def access?
    return false unless user.is_a?(User) && account_user && account.feature_enabled?('jrc_customer_master')
    return true if account_user.administrator?
    return true unless account_user.respond_to?(:custom_role_id) && account_user.custom_role_id.present?

    Array(account_user.custom_role&.permissions).include?('contact_manage')
  end

  def administer?
    access? && account_user.administrator?
  end
end
