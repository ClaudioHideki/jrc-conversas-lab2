class JrcRelationship::ModulePolicy < ApplicationPolicy
  PERMISSIONS = %w[jrc_relationship_view jrc_relationship_manage jrc_relationship_team jrc_relationship_configure
                   jrc_relationship_documents_view jrc_relationship_documents_manage].freeze

  def access?
    account&.active? && account_user && account.feature_enabled?('jrc_relationship') &&
      JrcCustomers::DirectoryPolicy.new(user_context, :directory).access? &&
      (admin? || account_user.custom_role_id.nil? || permission?('jrc_relationship_view'))
  end

  def manage?
    access? && (admin? || permission?('jrc_relationship_manage') || account_user.custom_role_id.nil?)
  end

  def team?
    access? && (admin? || permission?('jrc_relationship_team'))
  end

  def configure?
    access? && (admin? || permission?('jrc_relationship_configure'))
  end

  def admin?
    account_user&.administrator? && account_user.custom_role_id.nil?
  end

  def documents_view?
    access? && (admin? || permission?('jrc_relationship_documents_view') || permission?('jrc_relationship_documents_manage'))
  end

  def documents_manage?
    access? && (admin? || permission?('jrc_relationship_documents_manage'))
  end

  def permission?(key)
    Array(account_user&.custom_role&.permissions).include?(key)
  end
end
