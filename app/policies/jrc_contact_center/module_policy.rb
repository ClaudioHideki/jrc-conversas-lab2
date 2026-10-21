# frozen_string_literal: true

class JrcContactCenter::ModulePolicy < ApplicationPolicy
  PERMISSIONS = %w[
    jrc_contact_center_view
    jrc_contact_center_operate
    jrc_contact_center_supervise
    jrc_contact_center_configure
    jrc_contact_center_reports
  ].freeze

  def access?
    account&.active? && account_user && account.feature_enabled?('jrc_contact_center') &&
      (native_role? || permission?('jrc_contact_center_view'))
  end

  def operate?
    access? && (native_role? || permission?('jrc_contact_center_operate'))
  end

  def supervise?
    access? && (administrator? || permission?('jrc_contact_center_supervise'))
  end

  def configure?
    access? && (administrator? || permission?('jrc_contact_center_configure'))
  end

  def control?
    supervise? || configure?
  end

  def reports?
    access? && (administrator? || permission?('jrc_contact_center_reports') || permission?('jrc_contact_center_supervise'))
  end

  private

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
