class JrcRelationship::ModulePolicy < ApplicationPolicy
  PERMISSIONS = %w[jrc_relationship_view jrc_relationship_manage jrc_relationship_team jrc_relationship_configure
                   jrc_relationship_documents_view jrc_relationship_documents_manage jrc_relationship_export
                   jrc_relationship_documents_download jrc_relationship_documents_restricted].freeze

  def access?
    account&.active? && eligible_member? && account.feature_enabled?('jrc_relationship') &&
      JrcCustomers::DirectoryPolicy.new(user_context, :directory).access? &&
      (admin? || account_user.custom_role_id.nil? || permission?('jrc_relationship_view')) && local?('view')
  end

  def manage?
    access? && (admin? || permission?('jrc_relationship_manage') || account_user.custom_role_id.nil?) && local?('work')
  end

  def team?
    access? && (admin? || permission?('jrc_relationship_team')) && local?('team')
  end

  def configure?
    access? && (admin? || permission?('jrc_relationship_configure')) && local?('configure')
  end

  def admin?
    account_user&.administrator? && account_user.custom_role_id.nil?
  end

  def documents_view?
    access? && (admin? || permission?('jrc_relationship_documents_view') || permission?('jrc_relationship_documents_manage')) && local?('document_view')
  end

  def documents_manage?
    access? && (admin? || permission?('jrc_relationship_documents_manage')) && local?('document_manage')
  end

  def documents_upload?
    documents_view? && (admin? || permission?('jrc_relationship_documents_manage')) && local?('document_upload')
  end

  def documents_replace?
    documents_view? && (admin? || permission?('jrc_relationship_documents_manage')) && local?('document_replace')
  end

  def export?
    access? && (admin? || permission?('jrc_relationship_export')) && local?('export_data')
  end

  def export_history?
    access? && (admin? || permission?('jrc_relationship_export')) && local?('export_history')
  end

  def documents_download?
    documents_view? && (admin? || permission?('jrc_relationship_documents_download')) && local?('document_download')
  end

  def documents_restricted?
    documents_view? && (admin? || permission?('jrc_relationship_documents_restricted'))
  end

  def local?(action)
    account_user && JrcRelationship::LocalAccess.account_allowed?(account_user, action)
  end

  def permission?(key)
    Array(account_user&.custom_role&.permissions).include?(key)
  end

  private

  def eligible_member?
    account_user && user && JrcRelationship::AnalystEligibility.available?(account.id, user.id)
  end
end
