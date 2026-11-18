require 'rails_helper'

RSpec.describe JrcContactCenter::PauseCatalog do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:catalog) { described_class.new(account: account) }
  let(:manager) { JrcContactCenter::AgentStateManager.new(account: account, account_user: member) }
  let(:definition) do
    { 'code' => 'synthetic_break', 'name' => 'SYNTHETIC pausa', 'category' => 'SYNTHETIC', 'description' => '', 'active' => true,
      'minimum_minutes' => 15, 'default_minutes' => 30, 'maximum_minutes' => 60, 'unit_ids' => [], 'custom_role_ids' => [] }
  end

  before do
    account.enable_features!('jrc_contact_center', 'audit_logs')
    Current.user = actor
  end

  after { Current.reset }

  it 'keeps an absent catalog disabled and accepts a free legacy reason through the existing manager' do
    expect(catalog.call).to include('enforced' => false, 'entries' => [], 'version' => 0)
    event = manager.transition(state: 'paused', reason_code: 'legacy-custom-reason', command_id: SecureRandom.uuid, expected_state_version: '0')
    expect(event.reason_code).to eq('legacy-custom-reason')
    expect(event.metadata).not_to have_key('pause_definition')
    expect(account.reload.settings).not_to have_key(described_class::KEY)
  end

  it 'persists real minutes and has the same revision after the JSONB round trip without changing unrelated settings' do
    account.update!(settings: account.settings.merge('synthetic_existing' => { 'preserved' => true }))
    previous = catalog.revision
    saved = catalog.update!({ 'enforced' => false, 'entries' => [definition] }, expected_revision: previous)
    expect(saved.fetch('entries').sole).to eq(definition)
    expect(saved.fetch('revision')).not_to eq(previous)
    account.reload
    expect(described_class.new(account: account).revision).to eq(saved.fetch('revision'))
    expect(account.settings.fetch('synthetic_existing')).to eq('preserved' => true)
  end

  it 'requires explicit activation and keeps configuration and audit unchanged when it is absent' do
    previous = account.settings.deep_dup
    expect do
      catalog.update!({ 'enforced' => true, 'entries' => [definition] }, expected_revision: catalog.revision)
    end.to raise_error(JrcContactCenter::OperationError, 'pause_activation_confirmation_required')
    expect(account.reload.settings).to eq(previous)
    expect(Audited.audit_class.where(associated: account, comment: JrcContactCenter::ConfigurationAudit::PAUSE_COMMENT)).to be_empty
  end

  it 'rejects unknown reasons only for new transitions after explicit activation' do
    catalog.update!({ 'enforced' => true, 'entries' => [definition] }, expected_revision: catalog.revision, activation_confirmed: true)
    expect do
      manager.transition(state: 'paused', reason_code: 'unknown', command_id: SecureRandom.uuid, expected_state_version: '0')
    end.to raise_error(JrcContactCenter::OperationError, 'pause_reason_not_allowed')
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
    event = manager.transition(state: 'paused', reason_code: definition.fetch('code'), command_id: SecureRandom.uuid, expected_state_version: '0')
    expect(event.metadata.fetch('pause_definition')).to include('name' => definition.fetch('name'), 'default_minutes' => 30)
  end

  it 'preserves an exact legacy replay after activation without creating another event or rewriting history' do
    command = SecureRandom.uuid
    event = manager.transition(state: 'paused', reason_code: 'legacy-free', command_id: command, expected_state_version: '0')
    original = event.attributes.deep_dup
    catalog.update!({ 'enforced' => true, 'entries' => [definition] }, expected_revision: catalog.revision, activation_confirmed: true)
    replay = manager.transition(state: 'paused', reason_code: 'legacy-free', command_id: command, expected_state_version: '0')
    expect(replay.id).to eq(event.id)
    expect(event.reload.attributes).to eq(original)
    expect(JrcContactCenter::AgentStateEvent.where(account: account).count).to eq(1)
  end

  it 'does not let a saved receipt bypass current operating eligibility' do
    command = SecureRandom.uuid
    event = manager.transition(state: 'paused', reason_code: 'legacy-free', command_id: command, expected_state_version: '0')
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).update!(eligible: false)
    expect do
      manager.transition(state: 'paused', reason_code: 'legacy-free', command_id: command, expected_state_version: '0')
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(event.reload.reason_code).to eq('legacy-free')
  end

  it 'keeps the event definition immutable when the catalog label, time or active state later changes' do
    catalog.update!({ 'enforced' => true, 'entries' => [definition] }, expected_revision: catalog.revision, activation_confirmed: true)
    event = manager.transition(state: 'paused', reason_code: definition.fetch('code'), command_id: SecureRandom.uuid, expected_state_version: '0')
    previous = event.attributes.deep_dup
    changed = definition.merge('name' => 'SYNTHETIC new label', 'maximum_minutes' => 120)
    catalog.update!({ 'enforced' => true, 'entries' => [changed] }, expected_revision: catalog.revision)
    expect(event.reload.attributes).to eq(previous)
    expect(member.reload.availability).to eq('busy')
  end

  it 'does not reject provider history or pretend that a local catalog is a provider acknowledgement' do
    catalog.update!({ 'enforced' => true, 'entries' => [definition] }, expected_revision: catalog.revision, activation_confirmed: true)
    event = manager.record_provider_event(state: 'paused', occurred_at: Time.current, external_event_id: SecureRandom.uuid,
                                          provider: 'synthetic-provider', reason_code: 'unknown-provider-reason', derived: true)
    expect(event.reason_code).to eq('unknown-provider-reason')
    expect(event.metadata.fetch('provider_confirmed')).to be(false)
    expect(event.metadata).not_to have_key('pause_definition')
  end

  it 'does not activate a catalog whose only reason is inactive' do
    expect do
      catalog.update!({ 'enforced' => true, 'entries' => [definition.merge('active' => false)] },
                      expected_revision: catalog.revision, activation_confirmed: true)
    end.to raise_error(JrcContactCenter::OperationError, 'active_pause_reason_required')
    expect(account.reload.settings).not_to have_key(described_class::KEY)
  end

  [nil, false, 'true', [], { 'enforced' => false }, { 'version' => 1, 'enforced' => true, 'entries' => [false] }].each do |value|
    it "fails closed for malformed stored configuration #{value.inspect}" do
      account.update!(settings: account.settings.merge(described_class::KEY => value))
      expect { catalog.call }.to raise_error(JrcContactCenter::OperationError, 'invalid_pause_catalog_configuration')
    end
  end

  it 'rejects an outdated revision without changing entries or adding another audit' do
    stale = catalog.revision
    catalog.update!({ 'enforced' => false, 'entries' => [definition] }, expected_revision: stale)
    before = account.reload.settings.deep_dup
    expect do
      catalog.update!({ 'enforced' => false, 'entries' => [] }, expected_revision: stale)
    end.to raise_error(JrcContactCenter::OperationError, 'stale_configuration_revision')
    expect(account.reload.settings).to eq(before)
    expect(Audited.audit_class.where(associated: account, comment: JrcContactCenter::ConfigurationAudit::PAUSE_COMMENT).count).to eq(1)
  end

  it 'rejects a non-monotone time and identifies the inconsistent field without silently clamping it' do
    expect do
      catalog.update!({ 'enforced' => false, 'entries' => [definition.merge('maximum_minutes' => 10)] }, expected_revision: catalog.revision)
    end.to raise_error(JrcContactCenter::PauseReasonDefinition::Invalid) { |error| expect(error.fields).to include('maximum_minutes') }
    expect(account.reload.settings).not_to have_key(described_class::KEY)
  end

  it 'rejects a role from another account instead of granting eligibility from it' do
    other = create(:custom_role, account: create(:account))
    expect do
      catalog.update!({ 'enforced' => false, 'entries' => [definition.merge('custom_role_ids' => [other.id])] },
                      expected_revision: catalog.revision)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'intersects Unit-scoped reasons with native active queue memberships instead of the caller-provided relation alone' do
    unit_a = JrcContactCenter::Unit.create!(account: account, code: 'A', name: 'SYNTHETIC A', kind: 'sac')
    unit_b = JrcContactCenter::Unit.create!(account: account, code: 'B', name: 'SYNTHETIC B', kind: 'sac')
    queue = JrcContactCenter::Queue.create!(account: account, unit: unit_b, code: 'B', name: 'SYNTHETIC queue B')
    JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member)
    configured = definition.merge('unit_ids' => [unit_a.id])
    catalog.update!({ 'enforced' => true, 'entries' => [configured] }, expected_revision: catalog.revision, activation_confirmed: true)
    broad = JrcContactCenter::QueueMembership.where(account: account)
    expect(catalog.options(member: member, memberships: broad).fetch(:entries)).to be_empty
    expect do
      manager.transition(state: 'paused', reason_code: configured.fetch('code'), command_id: SecureRandom.uuid, expected_state_version: '0')
    end.to raise_error(JrcContactCenter::OperationError, 'pause_reason_not_allowed')
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end

  it 'keeps a configured profile filter independent of the native permission to operate' do
    account.enable_features!('custom_roles')
    selected = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_operate])
    other = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_operate])
    catalog.update!({ 'enforced' => true, 'entries' => [definition.merge('custom_role_ids' => [selected.id])] },
                    expected_revision: catalog.revision, activation_confirmed: true)
    member.update!(custom_role: other)
    expect do
      manager.transition(state: 'paused', reason_code: definition.fetch('code'), command_id: SecureRandom.uuid, expected_state_version: '0')
    end.to raise_error(JrcContactCenter::OperationError, 'pause_reason_not_allowed')
    member.update!(custom_role: selected)
    event = manager.transition(state: 'paused', reason_code: definition.fetch('code'), command_id: SecureRandom.uuid, expected_state_version: '0')
    expect(event.metadata.fetch('pause_definition').fetch('custom_role_ids')).to eq([selected.id])
  end

  it 'rejects a member of another Account when reading operator options, even for a globally scoped reason' do
    catalog.update!({ 'enforced' => false, 'entries' => [definition] }, expected_revision: catalog.revision)
    other = create(:account)
    outsider = create(:user, :contact_center_eligible, account: other, role: :administrator)
    foreign_member = other.account_users.find_by!(user: outsider)
    expect do
      catalog.options(member: foreign_member, memberships: JrcContactCenter::QueueMembership.all)
    end.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'returns detached configuration and protects the current event projection from another member' do
    catalog.update!({ 'enforced' => true, 'entries' => [definition] }, expected_revision: catalog.revision, activation_confirmed: true)
    returned = catalog.call
    returned.fetch('entries').first['name'].replace('SYNTHETIC mutated DTO')
    expect(catalog.call.fetch('entries').first.fetch('name')).to eq(definition.fetch('name'))
    event = manager.transition(state: 'paused', reason_code: definition.fetch('code'), command_id: SecureRandom.uuid, expected_state_version: '0')
    peer = create(:user, :contact_center_eligible, account: account)
    peer_member = account.account_users.find_by!(user: peer)
    result = JrcContactCenter::PauseDefinitionSnapshot.call(event: event, member: peer_member, memberships: JrcContactCenter::QueueMembership.all)
    expect(result).to be_nil
  end
  it 'does not apply a Unit-scoped reason to a different selected queue even when both memberships exist' do
    units = %w[A B].map do |code|
      JrcContactCenter::Unit.create!(account: account, code: code, name: "SYNTHETIC #{code}", kind: 'sac')
    end
    queues = units.map do |unit|
      queue = JrcContactCenter::Queue.create!(account: account, unit: unit, code: unit.code, name: unit.name)
      JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member)
      queue
    end
    catalog.update!({ 'enforced' => true, 'entries' => [definition.merge('unit_ids' => [units.last.id])] },
                    expected_revision: catalog.revision, activation_confirmed: true)
    expect do
      manager.transition(state: 'paused', reason_code: definition.fetch('code'), queue_id: queues.first.id,
                         command_id: SecureRandom.uuid, expected_state_version: '0')
    end.to raise_error(JrcContactCenter::OperationError, 'pause_reason_not_allowed')
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end
end
