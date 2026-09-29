# frozen_string_literal: true
require 'rails_helper'

RSpec.describe JrcServiceDesk::ConfigurationService do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  before { sd_as_admin! }
  let(:command) { described_class.new(user_context: sd_context) }
  let(:attributes) { { name: 'Administrative fixture', code: 'fixture-code', active: true } }
  def create_row(resource = 'categories', extra = {})
    command.create(resource: resource, unit_id: sd_unit.id, attributes: attributes.merge(extra), idempotency_key: SecureRandom.uuid)
  end

  it 'persists a catalogue and native audit atomically, without a new tenant or audit table' do
    result = create_row
    row = result.record.reload
    audit = Audited::Audit.find(result.audit_id)
    expect(row.unit_id).to eq(sd_unit.id)
    expect(row.account_id).to eq(sd_account.id)
    expect(audit.associated).to eq(sd_unit)
    expect(Audited::Audit.where(associated_type: 'Account', associated_id: sd_account.id, id: audit.id)).not_to exist
    expect(audit.user).to eq(sd_user)
    meta = JSON.parse(audit.comment)
    expect(meta.values_at('unit_id', 'membership_id', 'account_user_id')).to eq([sd_unit.id, sd_membership.id, sd_account_user.id])
    expect(meta['account_id']).to eq(sd_account.id)
    expect(meta['after']['active']).to be(true)
    expect(audit.created_at).to be_present
  end

  it 'replays the same key without a second record or audit, but rejects another intention' do
    key = SecureRandom.uuid
    a = command.create(resource: 'categories', unit_id: sd_unit.id, attributes: attributes, idempotency_key: key)
    expect { command.create(resource: 'categories', unit_id: sd_unit.id, attributes: attributes, idempotency_key: key) }.not_to change(Audited::Audit, :count)
    b = command.create(resource: 'categories', unit_id: sd_unit.id, attributes: attributes, idempotency_key: key)
    expect(b.record.id).to eq(a.record.id)
    expect { command.create(resource: 'categories', unit_id: sd_unit.id, attributes: attributes.merge(name: 'Changed'), idempotency_key: key) }.to raise_error(JrcServiceDesk::IdempotencyConflict)
  end

  it 'updates/deactivates/reactivates with a fresh revision, preserving code and identity' do
    result = create_row
    row = result.record
    revision = JrcServiceDesk::ConfigurationResources.revision('categories', row)
    result = command.update(resource: 'categories', record_id: row.id, attributes: { active: false }, expected_revision: revision, idempotency_key: SecureRandom.uuid)
    expect(row.reload.active).to be(false)
    expect(row.code).to eq(attributes[:code])
    expect { command.update(resource: 'categories', record_id: row.id, attributes: { name: 'Stale' }, expected_revision: revision, idempotency_key: SecureRandom.uuid) }.to raise_error(JrcServiceDesk::IdempotencyConflict)
    command.update(resource: 'categories', record_id: row.id, attributes: { active: true }, expected_revision: JrcServiceDesk::ConfigurationResources.revision('categories', row), idempotency_key: SecureRandom.uuid)
    expect(row.reload.active).to be(true)
    expect(Audited::Audit.find(result.audit_id).audited_changes['active']).to eq([true, false])
  end

  it 'rolls back the record when native audit persistence fails' do
    allow(Audited::Audit).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Audited::Audit.new))
    expect { create_row }.to raise_error(ActiveRecord::RecordInvalid)
    expect(JrcServiceDesk::Category.where(unit_id: sd_unit.id)).to be_empty
  end

  it 'rejects another Account and preserves administrative access without operational membership' do
    [sd_foreign_unit].each do |unit|
      expect { command.create(resource: 'categories', unit_id: unit.id, attributes: attributes, idempotency_key: SecureRandom.uuid) }.to raise_error(ActiveRecord::RecordNotFound)
    end
    sd_membership.update!(active: false)
    expect(create_row.record.unit_id).to eq(sd_unit.id)
    expect(sd_membership.reload.active).to be(false)
  end

  it 'denies an agent with membership but no management capability' do
    sd_account_user.update!(role: :agent)
    expect { create_row }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'denies revocation of flag/capability on an idempotent replay' do
    key = SecureRandom.uuid
    command.create(resource: 'categories', unit_id: sd_unit.id, attributes: attributes, idempotency_key: key)
    sd_account.disable_features!('jrc_service_desk')
    expect { command.create(resource: 'categories', unit_id: sd_unit.id, attributes: attributes, idempotency_key: key) }.to raise_error(Pundit::NotAuthorizedError)
    sd_account.enable_features!('jrc_service_desk'); sd_account_user.update!(role: :agent)
    expect { command.create(resource: 'categories', unit_id: sd_unit.id, attributes: attributes, idempotency_key: key) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rejects cross-account team assignment before writing' do
    foreign_team = create(:team, account: sd_foreign_account)
    expect { create_row('queues', team_id: foreign_team.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcServiceDesk::Queue.where(unit_id: sd_unit.id)).to be_empty
  end

  it 'does not reinterpret a phase referenced in an immutable policy, even before tickets exist' do
    lc_publish
    row = lc_statuses[:working]
    expect { command.update(resource: 'statuses', record_id: row.id, attributes: { phase: 'resolved' },
      expected_revision: JrcServiceDesk::ConfigurationResources.revision('statuses', row), idempotency_key: SecureRandom.uuid) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(row.reload.phase).to eq('open')
  end

  it 'allows explicit policy disabling with inactive historical statuses without rewriting its old version' do
    policy = lc_publish
    old = policy.current_version
    sd_as_admin!
    lc_statuses[:resolved].update!(active: false)
    changed = JrcServiceDesk::PublishLifecyclePolicyService.new(user_context: sd_context).call(unit_id: sd_unit.id,
      attributes: { name: policy.name, enabled: false, service_id: nil, expected_version: 1, definition: old.definition })
    expect(changed.enabled).to be(false)
    expect(changed.current_version.version).to eq(2)
    expect(old.reload.publication['enabled']).to be(true)
    expect(old.definition).to eq(changed.current_version.definition)
  end

  it 'does not let callers create structural units, alter ownership or physically delete a record' do
    expect { create_row('units') }.to raise_error(KeyError)
    expect { create_row('categories', account_id: sd_foreign_account.id) }.to raise_error(ArgumentError)
    expect(command).not_to respond_to(:destroy)
  end
end
