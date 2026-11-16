# frozen_string_literal: true

# Keep Call Center capability changes in the existing transactional audit store.
# Never copy arbitrary role descriptions, provider settings or credentials.
module Enterprise::Audit::ContactCenterCustomRole
  extend ActiveSupport::Concern

  included do
    after_create :audit_contact_center_permissions_create
    after_update :audit_contact_center_permissions_update
    before_destroy :audit_contact_center_permissions_destroy, prepend: true
  end

  private

  def contact_center_permissions(values)
    Array(values).intersection(::JrcContactCenter::ModulePolicy::PERMISSIONS).sort
  end

  def audit_contact_center_permissions_create
    audit_contact_center_permissions('create', [], permissions)
  end

  def audit_contact_center_permissions_update
    return unless saved_change_to_permissions?

    before, after = saved_change_to_permissions
    audit_contact_center_permissions('update', before, after)
  end

  def audit_contact_center_permissions_destroy
    audit_contact_center_permissions('destroy', permissions, [])
  end

  def audit_contact_center_permissions(action, before, after)
    before = contact_center_permissions(before)
    after = contact_center_permissions(after)
    return if before == after

    Enterprise::AuditLog.create!(
      auditable: self, associated: account, user: Current.user, action: action,
      audited_changes: { 'permissions' => [before, after] }, comment: 'JRC Call Center native capabilities'
    )
  end
end
