# frozen_string_literal: true

# Only native CustomRole mutations involving SD permissions add an audit entry.
# This uses the existing audit table; it is not an authorization/grant store.
module Enterprise::Audit::ServiceDeskCustomRole
  extend ActiveSupport::Concern

  included do
    after_create :audit_service_desk_permissions_create
    after_update :audit_service_desk_permissions_update
    before_destroy :audit_service_desk_permissions_destroy, prepend: true
  end

  private

  def service_desk_permissions(values)
    Array(values).select { |value| ::JrcServiceDesk::Capabilities::PERMISSIONS.include?(value) }.sort
  end

  def audit_service_desk_permissions_create
    audit_service_desk_permissions('create', [], permissions)
  end

  def audit_service_desk_permissions_update
    return unless saved_change_to_permissions?
    before, after = saved_change_to_permissions
    audit_service_desk_permissions('update', before, after)
  end

  def audit_service_desk_permissions_destroy
    audit_service_desk_permissions('destroy', permissions, [])
  end

  def audit_service_desk_permissions(action, before, after)
    before = service_desk_permissions(before)
    after = service_desk_permissions(after)
    return if before == after

    Enterprise::AuditLog.create!(auditable: self, associated: account, user: Current.user,
      action: action, audited_changes: { 'permissions' => [before, after] },
      comment: 'JRC Service Desk native capabilities')
  end
end
