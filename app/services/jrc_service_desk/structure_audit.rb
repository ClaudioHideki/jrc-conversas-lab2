# frozen_string_literal: true

# Same Audited table as CP6. Associated with SD objects, NOT Account.associated_audits.
class JrcServiceDesk::StructureAudit
  NAMESPACE = 'jrc_service_desk_structure_v1'

  def initialize(account:, actor:, account_user: nil)
    @account, @actor, @account_user = account, actor, account_user
  end

  def uuid(key)
    'jrc-sd-structure-' + JrcServiceDesk::CanonicalJson.digest('account_id' => @account.id,
      'user_id' => @actor.id, 'key' => JrcServiceDesk::Input.request_key(key))
  end

  def prior(key)
    scope.where(request_uuid: uuid(key)).first
  end

  def write!(resource:, record:, before:, key:, fingerprint:, reason:)
    after = JrcServiceDesk::StructureRecords.attributes(resource, record)
    metadata = { 'namespace' => NAMESPACE, 'account_id' => @account.id, 'unit_id' => unit_id(record),
      'author_user_id' => @actor.id, 'author_account_user_id' => @account_user&.id,
      'resource' => resource, 'record_id' => record.id, 'reason' => reason, 'fingerprint' => fingerprint,
      'before' => before, 'after' => after }
    changes = before.nil? ? after : after.to_h { |k, v| [k, [before[k], v]] }.reject { |_k, pair| pair[0] == pair[1] }
    Audited::Audit.create!(auditable: record, associated: associated(record), user: @actor,
      action: before.nil? ? 'create' : 'update', audited_changes: changes,
      comment: JrcServiceDesk::CanonicalJson.dump(metadata), request_uuid: uuid(key))
  end

  def metadata(audit)
    value = JSON.parse(audit.comment.to_s)
    raise ActiveRecord::RecordNotFound unless value.is_a?(Hash) && value['namespace'] == NAMESPACE &&
      value['account_id'] == @account.id && value['author_user_id'] == @actor.id && value['author_account_user_id'] == @account_user&.id
    value
  rescue JSON::ParserError
    raise ActiveRecord::RecordNotFound
  end

  def receipt(resource, record, audit_id)
    audit = scope.where(auditable_type: record.class.base_class.name, auditable_id: record.id).find(JrcServiceDesk::Input.id(audit_id))
    value = metadata(audit)
    raise ActiveRecord::RecordNotFound unless value['resource'] == resource && value['record_id'] == record.id
    value.merge('id' => audit.id.to_s, 'action' => audit.action, 'occurred_at' => audit.created_at.iso8601(6))
  end

  private

  def scope
    Audited::Audit.where(user_type: @actor.class.base_class.name, user_id: @actor.id)
  end

  def unit_id(record)
    return record.id if record.is_a?(JrcServiceDesk::Unit)
    record.respond_to?(:unit_id) ? record.unit_id : nil
  end

  def associated(record)
    record.is_a?(JrcServiceDesk::UnitMembership) ? record.unit : record
  end
end
