require 'rails_helper'

RSpec.describe JrcContactCenter::AgentStateManager do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:catalog) { JrcContactCenter::PauseCatalog.new(account: account) }
  let(:manager) { described_class.new(account: account, account_user: member) }
  let(:definition) do
    { 'code' => 'synthetic_break', 'name' => 'SYNTHETIC private pause', 'category' => 'SYNTHETIC', 'description' => '', 'active' => true,
      'minimum_minutes' => 0, 'default_minutes' => 30, 'maximum_minutes' => 60, 'unit_ids' => [], 'custom_role_ids' => [] }
  end
  let(:command) { SecureRandom.uuid }
  let(:attributes) { { state: 'paused', reason_code: definition.fetch('code'), command_id: command, expected_state_version: '0' } }

  before do
    account.enable_features!('jrc_contact_center', 'audit_logs')
    Current.user = actor
  end

  after { Current.reset }

  it 'keeps the persisted old shape and its exact original revision on a read or unchanged save' do
    catalog.update!({ 'enforced' => false, 'entries' => [definition] }, expected_revision: catalog.revision)
    stored = account.reload.settings.fetch(JrcContactCenter::PauseCatalog::KEY).deep_dup
    rows = stored.fetch('entries').map { |row| JrcContactCenter::PauseReasonDefinition::FIELDS.map { |field| row[field] } }
    expected = Digest::SHA256.hexdigest([JrcContactCenter::PauseCatalog::KEY, account.id, stored.fetch('version'), false, rows].to_json)
    expect(catalog.revision).to eq(expected)
    catalog.call
    catalog.update!(stored.slice('enforced', 'entries'), expected_revision: expected)
    expect(account.reload.settings.fetch(JrcContactCenter::PauseCatalog::KEY)).to eq(stored)
    expect(Audited.audit_class.where(associated: account, comment: JrcContactCenter::ConfigurationAudit::PAUSE_COMMENT).count).to eq(1)
  end

  it 'does not require the new option until account enforcement is explicitly activated' do
    configured = definition.merge('justification_required' => true)
    catalog.update!({ 'enforced' => false, 'entries' => [configured] }, expected_revision: catalog.revision)
    event = manager.transition(**attributes)
    expect(event.metadata).not_to have_key('pause_justification')
    expect(event.metadata.dig('pause_definition', 'justification_required')).to be(true)
  end

  it 'does not reinterpret an old receipt after enabling justification and preserves the old digest bytes' do
    event = manager.transition(**attributes)
    previous = event.attributes.deep_dup
    configured = definition.merge('justification_required' => true)
    catalog.update!({ 'enforced' => true, 'entries' => [configured] }, expected_revision: catalog.revision, activation_confirmed: true)
    replay = manager.transition(**attributes, justification: '   ')
    expect(replay.id).to eq(event.id)
    expect(event.reload.attributes).to eq(previous)
    expect(JrcContactCenter::AgentStateEvent.where(account: account).count).to eq(1)
  end

  it 'requires a nonblank justification without inserting an event or altering availability' do
    catalog.update!({ 'enforced' => true, 'entries' => [definition.merge('justification_required' => true)] },
                    expected_revision: catalog.revision, activation_confirmed: true)
    previous = member.reload.availability
    expect { manager.transition(**attributes) }.to raise_error(JrcContactCenter::OperationError, 'pause_justification_required')
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
    expect(member.reload.availability).to eq(previous)
  end

  [false, 3, [], {}, 'x' * 1001].each do |invalid|
    it "rejects malformed or oversized justification #{invalid.class} without a state write" do
      expect do
        manager.transition(**attributes, justification: invalid)
      end.to raise_error(JrcContactCenter::OperationError, 'invalid_pause_justification')
      expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
    end
  end

  it 'stores a bounded private justification only in the native event and returns it only in the own authorized projection' do
    catalog.update!({ 'enforced' => true, 'entries' => [definition.merge('justification_required' => true)] },
                    expected_revision: catalog.revision, activation_confirmed: true)
    event = manager.transition(**attributes, justification: '  SYNTHETIC private explanation  ')
    expect(event.metadata.fetch('pause_justification')).to eq('SYNTHETIC private explanation')
    expect(event.metadata.fetch('provider_confirmed')).to be(false)
    snapshot = JrcContactCenter::AgentStateSnapshot.new(account_user: member)
    expect(snapshot.operator_payload.dig(:pause_definition, 'justification')).to eq('SYNTHETIC private explanation')
    expect(snapshot.call.to_json).not_to include('SYNTHETIC private explanation')
    other_account = create(:account)
    other_actor = create(:user, :contact_center_eligible, account: other_account, role: :administrator)
    other = other_account.account_users.find_by!(user: other_actor)
    memberships = JrcContactCenter::QueueMembership.where(account: other.account)
    expect(JrcContactCenter::PauseDefinitionSnapshot.call(event: event, member: other, memberships: memberships)).to be_nil
  end

  it 'replays the same private receipt once and rejects changed text without duplicating the event' do
    catalog.update!({ 'enforced' => true, 'entries' => [definition] }, expected_revision: catalog.revision, activation_confirmed: true)
    event = manager.transition(**attributes, justification: 'SYNTHETIC first')
    expect(manager.transition(**attributes, justification: 'SYNTHETIC first').id).to eq(event.id)
    expect do
      manager.transition(**attributes, justification: 'SYNTHETIC changed')
    end.to raise_error(JrcContactCenter::OperationError, 'command_id_conflict')
    expect(JrcContactCenter::AgentStateEvent.where(account: account).count).to eq(1)
  end

  it 'hides private historical text after loss of operating authority without rewriting history' do
    catalog.update!({ 'enforced' => true, 'entries' => [definition] }, expected_revision: catalog.revision, activation_confirmed: true)
    event = manager.transition(**attributes, justification: 'SYNTHETIC private revoked')
    previous = event.attributes.deep_dup
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).update!(eligible: false)
    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member.reload).operator_payload[:pause_definition]).to be_nil
    expect(event.reload.attributes).to eq(previous)
  end

  it 'filters private request text from the existing native parameter logging without a new logging exception' do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    redacted = filter.filter('agent_state' => { 'justification' => 'SYNTHETIC private log' })
    expect(redacted.dig('agent_state', 'justification')).to eq('[FILTERED]')
    expect(redacted.to_json).not_to include('SYNTHETIC private log')
  end

  [nil, 'true', 1, [], {}].each do |invalid|
    it "rejects nonboolean catalog justification policy #{invalid.inspect}" do
      expect do
        catalog.update!({ 'enforced' => false, 'entries' => [definition.merge('justification_required' => invalid)] },
                        expected_revision: catalog.revision)
      end.to raise_error(JrcContactCenter::PauseReasonDefinition::Invalid)
      expect(account.reload.settings).not_to have_key(JrcContactCenter::PauseCatalog::KEY)
    end
  end

  it 'does not silently store private text for an unknown legacy reason that has no authorized private projection' do
    expect do
      manager.transition(**attributes, justification: 'SYNTHETIC unmatched private text')
    end.to raise_error(JrcContactCenter::OperationError, 'pause_reason_not_allowed')
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end
end
