# frozen_string_literal: true

class JrcContactCenter::ModulePolicy < ApplicationPolicy
  PERMISSIONS = %w[
    jrc_contact_center_view
    jrc_contact_center_operate
    jrc_contact_center_supervise
    jrc_contact_center_configure
    jrc_contact_center_reports
    jrc_contact_center_administer
    jrc_contact_center_monitor
    jrc_contact_center_recordings_view
    jrc_contact_center_recordings_listen
    jrc_contact_center_recordings_download
    jrc_contact_center_publish
    jrc_contact_center_approve
    jrc_contact_center_audit
  ].freeze

  def access?
    account&.active? && account_user&.account_id == account.id && account.feature_enabled?('jrc_contact_center') &&
      account_user.user_id == user&.id && sources.eligible? && allowed?('view', native: native_role?)
  end

  def operate?
    access? && allowed?('operate', native: native_role?)
  end

  def supervise?
    access? && allowed?('supervise', native: administrator?)
  end

  def configure?
    access? && !sources.denied?('jrc_contact_center_configure') &&
      (allowed?('configure', native: administrator?) || allowed?('administer'))
  end

  def control?
    supervise? || configure?
  end

  def reports?
    access? && !sources.denied?('jrc_contact_center_reports') &&
      (allowed?('reports', native: administrator?) || allowed?('supervise'))
  end

  # These are new authorities, not aliases for administrator/configure/report.
  %w[administer monitor publish approve audit].each do |action|
    define_method("#{action}?") { access? && allowed?(action) }
  end

  def recordings_view?
    access? && allowed?('recordings_view')
  end

  def recordings_listen?
    recordings_view? && allowed?('recordings_listen')
  end

  def recordings_download?
    recordings_view? && allowed?('recordings_download')
  end

  def effective_permissions
    PERMISSIONS.select do |permission|
      action = permission.delete_prefix('jrc_contact_center_')
      public_send("#{action == 'view' ? 'access' : action}?")
    end
  end

  private

  def native_role?
    account_user.custom_role_id.nil?
  end

  def administrator?
    account_user.administrator? && account_user.custom_role_id.nil?
  end

  def allowed?(action, native: false)
    key = "jrc_contact_center_#{action}"
    !sources.denied?(key) && (native || sources.granted?(key))
  end

  def sources
    options = { account: account, member: account_user }
    options[:individual] = user_context[:cc_access_preview] if user_context.key?(:cc_access_preview)
    @sources ||= JrcContactCenter::PermissionSources.new(**options)
  end
end
