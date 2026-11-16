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
    account&.active? && account_user && account.feature_enabled?('jrc_contact_center') &&
      (administrator? || permission?('jrc_contact_center_view') || assigned_operator?)
  end

  def operate?
    access? && (native_role? || permission?('jrc_contact_center_operate'))
  end

  def supervise?
    access? && (administrator? || permission?('jrc_contact_center_supervise'))
  end

  def configure?
    access? && (administrator? || permission?('jrc_contact_center_configure') || permission?('jrc_contact_center_administer'))
  end

  def control?
    supervise? || configure?
  end

  def reports?
    access? && (administrator? || permission?('jrc_contact_center_reports') || permission?('jrc_contact_center_supervise'))
  end

  # These are new authorities, not aliases for administrator/configure/report.
  %w[administer monitor publish approve audit].each do |action|
    define_method("#{action}?") { access? && permission?("jrc_contact_center_#{action}") }
  end

  def recordings_view?
    access? && permission?('jrc_contact_center_recordings_view')
  end

  def recordings_listen?
    recordings_view? && permission?('jrc_contact_center_recordings_listen')
  end

  def recordings_download?
    recordings_view? && permission?('jrc_contact_center_recordings_download')
  end

  private

  def assigned_operator?
    return false unless native_role?

    now = Time.current
    memberships = JrcContactCenter::QueueMembership.where(account: account, account_user: account_user, active: true)
    memberships.where('starts_at IS NULL OR starts_at <= ?', now).where('ends_at IS NULL OR ends_at > ?', now).exists? ||
      JrcContactCenter::CallLeg.exists?(account: account, account_user: account_user)
  end

  def native_role?
    account_user.custom_role_id.nil?
  end

  def administrator?
    account_user.administrator? && account_user.custom_role_id.nil?
  end

  def permission?(key)
    Array(account_user.custom_role&.permissions).include?(key)
  end
end
