# frozen_string_literal: true

# Reuse the installed native audits table. No second audit store or RBAC is created.
# Calls belong to the same transaction/unit lock as the mutation. No public undo/delete.
class JrcServiceDesk::ConfigurationAudit
  NAMESPACE = 'jrc_service_desk_configuration_v1'

  def initialize(context:, membership:)
    @context, @membership = context, membership
  end

  def request_uuid(key)
    "jrc-sd-config-#{JrcServiceDesk::CanonicalJson.digest('account' => @context.account.id, 'unit' => @membership.unit_id,
      'actor' => @membership.id, 'key' => JrcServiceDesk::Input.request_key(key))}"
  end

  def prior(key)
    scope.where(request_uuid: request_uuid(key)).first
  end

  def receipt(resource, record, audit_id)
    audit = scope.where(auditable_type: record.class.base_class.name, auditable_id: record.id).find(JrcServiceDesk::Input.id(audit_id))
    info = metadata(audit)
    raise ActiveRecord::RecordNotFound unless info['resource'] == resource && info['unit_id'] == record.unit_id && info['namespace'] == NAMESPACE
    { id: audit.id.to_s, account_id: record.account_id.to_s, unit_id: record.unit_id.to_s,
      record_id: record.id.to_s, resource: resource, action: audit.action, author_account_user_id: @context.account_user.id.to_s,
      occurred_at: audit.created_at.iso8601(6), before: info['before'], after: info['after'], fingerprint: info['fingerprint'] }
  end

  def write!(resource:, record:, action:, before:, after:, key:, fingerprint:)
    metadata = { 'namespace' => NAMESPACE, 'account_id' => record.account_id, 'unit_id' => record.unit_id, 'account_user_id' => @context.account_user.id,
      'membership_id' => @membership.id, 'resource' => resource, 'fingerprint' => fingerprint, 'before' => before, 'after' => after }
    changes = action == 'create' ? after : after.to_h { |field, value| [field, [before[field], value]] }.reject { |_field, pair| pair.first == pair.last }
    Audited::Audit.create!(auditable: record, associated: record.unit, user: @context.user,
      action: action, audited_changes: changes, comment: JrcServiceDesk::CanonicalJson.dump(metadata), request_uuid: request_uuid(key))
  end

  def metadata(audit)
    info = JSON.parse(audit.comment.to_s)
    raise ActiveRecord::RecordNotFound unless info.is_a?(Hash) && info['namespace'] == NAMESPACE &&
      info['account_id'] == @context.account.id && info['unit_id'] == @membership.unit_id && info['membership_id'] == @membership.id && info['account_user_id'] == @context.account_user.id
    info
  rescue JSON::ParserError
    raise ActiveRecord::RecordNotFound
  end

  private

  def scope
    # Do not attach unit-private before/after values to Account.associated_audits.
    # The existing Account-wide audit endpoint has no UnitMembership filter.
    Audited::Audit.where(associated_type: JrcServiceDesk::Unit.base_class.name, associated_id: @membership.unit_id,
      user_type: @context.user.class.base_class.name, user_id: @context.user.id)
  end
end
