# frozen_string_literal: true

# No bootstrap, unit grants, physical deletions, dynamic constantize or arbitrary attributes.
class JrcServiceDesk::ConfigurationService < JrcServiceDesk::BaseService
  Result = Struct.new(:record, :audit_id, keyword_init: true)

  def create(resource:, unit_id:, attributes:, idempotency_key:)
    resource = resource.to_s
    model = JrcServiceDesk::ConfigurationResources.model(resource)
    values = JrcServiceDesk::ConfigurationContract.attributes(resource, attributes, create: true)
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    fingerprint = JrcServiceDesk::CanonicalJson.digest('action' => 'create', 'resource' => resource, 'attributes' => values)
    with_unit(unit_id, administrative: true) do |unit|
      candidate = model.new(account: context.account, unit: unit)
      authorize!(candidate, :create?)
      existing = replay(resource, key, fingerprint)
      next existing if existing
      values['team_id'] = native_team(values['team_id'])&.id if values.key?('team_id')
      candidate.assign_attributes(values)
      save_catalogue!(candidate)
      audit = auditor.write!(resource: resource, record: candidate, action: 'create', before: {},
        after: JrcServiceDesk::ConfigurationResources.fields(resource, candidate), key: key, fingerprint: fingerprint)
      Result.new(record: candidate, audit_id: audit.id)
    end
  end

  def update(resource:, record_id:, attributes:, expected_revision:, idempotency_key:)
    resource = resource.to_s
    model = JrcServiceDesk::ConfigurationResources.model(resource)
    values = JrcServiceDesk::ConfigurationContract.attributes(resource, attributes, create: false)
    expected_revision = JrcServiceDesk::ConfigurationContract.revision(expected_revision)
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    id = JrcServiceDesk::Input.id(record_id)
    fingerprint = JrcServiceDesk::CanonicalJson.digest('action' => 'update', 'resource' => resource, 'id' => id,
      'attributes' => values, 'revision' => expected_revision)
    initial = fresh_context!
    candidate = Pundit.policy_scope!(initial.to_h, model).find(id)
    with_unit(candidate.unit_id, administrative: true) do |unit|
      record = Pundit.policy_scope!(context.to_h, model).where(unit_id: unit.id).lock.find(id)
      authorize!(record, :update?)
      existing = replay(resource, key, fingerprint)
      next existing if existing
      unless JrcServiceDesk::ConfigurationResources.revision(resource, record) == expected_revision
        raise JrcServiceDesk::IdempotencyConflict, 'Configuration changed; reload'
      end
      before = JrcServiceDesk::ConfigurationResources.fields(resource, record)
      values['team_id'] = native_team(values['team_id'])&.id if values.key?('team_id')
      record.assign_attributes(values)
      save_catalogue!(record)
      audit = auditor.write!(resource: resource, record: record, action: 'update', before: before,
        after: JrcServiceDesk::ConfigurationResources.fields(resource, record), key: key, fingerprint: fingerprint)
      Result.new(record: record, audit_id: audit.id)
    end
  end

  private

  def save_catalogue!(record)
    JrcServiceDesk::CatalogueAccess.new(record).validate_configuration!(context) if record.is_a?(JrcServiceDesk::Service)
    record.save!
  end

  def auditor
    JrcServiceDesk::ConfigurationAudit.new(context: context, membership: actor_membership, unit: @acting_unit)
  end

  def replay(resource, key, fingerprint)
    prior = auditor.prior(key)
    return nil unless prior
    data = auditor.metadata(prior)
    raise JrcServiceDesk::IdempotencyConflict, 'Request key already used' unless data['fingerprint'] == fingerprint && data['resource'] == resource
    model = JrcServiceDesk::ConfigurationResources.model(resource)
    raise ActiveRecord::RecordNotFound unless prior.auditable_type == model.base_class.name
    record = Pundit.policy_scope!(context.to_h, model).where(unit_id: @acting_unit.id).find(prior.auditable_id)
    authorize!(record, :update?) # Replay must not restore a revoked management capability.
    Result.new(record: record, audit_id: prior.id)
  end
end
