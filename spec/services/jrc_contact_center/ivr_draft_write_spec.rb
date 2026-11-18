require 'rails_helper'

RSpec.describe JrcContactCenter::IvrDraftWrite do
  let(:account) { create(:account) }
  let(:operator) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: operator) }
  let(:context) { { account: account, account_user: member, user: operator } }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, code: 'LOCAL', name: 'SYNTHETIC local', kind: 'sac') }
  let(:definition) { { 'schema_version' => 1, 'start' => 'end', 'nodes' => [{ 'id' => 'end', 'type' => 'end' }] } }
  let(:values) { { name: 'SYNTHETIC local draft', status: 'draft', definition: definition, request_id: SecureRandom.uuid, expected_revision: 0 } }
  let(:input) { JrcContactCenter::IvrDraftInput.new(**values) }
  let(:writer) { described_class.new(context: context) }

  before { account.enable_features!('jrc_contact_center') }

  it 'creates the local identity, immutable initial revision and redacted audit in the same transaction' do
    result = writer.call(input: input, unit_id: unit.id)
    expect(result).to include(replayed: false, latest_revision: 1)
    expect(result[:version].definition).to eq(definition)
    expect(result[:version].integrity_sha256).to match(/\A[0-9a-f]{64}\z/)
  end

  it 'records the authenticated actor and scope without private graph or name in the native audit' do
    result = writer.call(input: input, unit_id: unit.id)
    audit = Audited.audit_class.find_by!(auditable: result[:version])
    expect(audit.user).to eq(operator)
    expect(audit.associated).to eq(account)
    expect(audit.audited_changes).to include('omitted_fields' => %w[name definition])
    expect(audit.audited_changes.fetch('attributes').last.keys).to contain_exactly('revision', 'status', 'integrity_sha256')
    expect(audit.audited_changes.to_json).not_to include('SYNTHETIC local draft', '"nodes"', '"start"')
    expect(audit.audited_changes.dig('cc_scope', 'after', 'unit_id')).to eq(unit.id.to_s)
  end

  it 'appends changes while preserving the earlier revision' do
    original = writer.call(input: input, unit_id: unit.id)
    updated = JrcContactCenter::IvrDraftInput.new(**values, name: 'SYNTHETIC revised', expected_revision: 1, request_id: SecureRandom.uuid)
    result = writer.call(input: updated, id: original[:draft].id)
    expect(result[:version].revision).to eq(2)
    expect(original[:version].reload.name).to eq('SYNTHETIC local draft')
    expect(original[:draft].latest_version.name).to eq('SYNTHETIC revised')
  end

  it 'replays the original create receipt without duplicating data or audit events' do
    original = writer.call(input: input, unit_id: unit.id)
    before = [JrcContactCenter::IvrDraft.count, JrcContactCenter::IvrDraftVersion.count, Audited.audit_class.count]
    result = writer.call(input: input, unit_id: unit.id)
    expect(result).to include(replayed: true, latest_revision: 1, version: original[:version])
    expect([JrcContactCenter::IvrDraft.count, JrcContactCenter::IvrDraftVersion.count, Audited.audit_class.count]).to eq(before)
  end

  it 'rejects reuse of a request identity for different data' do
    original = writer.call(input: input, unit_id: unit.id)
    changed = JrcContactCenter::IvrDraftInput.new(**values, name: 'SYNTHETIC different')
    expect { writer.call(input: changed, unit_id: unit.id) }.to raise_error(JrcContactCenter::OperationError, 'stale_ivr_revision')
    expect(original[:draft].versions.count).to eq(1)
  end

  it 'does not let a different administrator retrieve another actor receipt by guessing its request UUID' do
    writer.call(input: input, unit_id: unit.id)
    other = create(:user, :contact_center_eligible, account: account, role: :administrator)
    other_context = { account: account, account_user: account.account_users.find_by!(user: other), user: other }
    expect do
      described_class.new(context: other_context).call(input: input, unit_id: unit.id)
    end.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rejects an update whose revision no longer matches without overwriting the accepted version' do
    original = writer.call(input: input, unit_id: unit.id)
    stale = JrcContactCenter::IvrDraftInput.new(**values, request_id: SecureRandom.uuid)
    expect { writer.call(input: stale, id: original[:draft].id) }.to raise_error(JrcContactCenter::OperationError, 'stale_ivr_revision')
    expect(original[:draft].versions.count).to eq(1)
  end

  it 'distinguishes an idempotent update receipt from a newer current head' do
    original = writer.call(input: input, unit_id: unit.id)
    second = JrcContactCenter::IvrDraftInput.new(**values, expected_revision: 1, name: 'SYNTHETIC second', request_id: SecureRandom.uuid)
    writer.call(input: second, id: original[:draft].id)
    third = JrcContactCenter::IvrDraftInput.new(**values, expected_revision: 2, name: 'SYNTHETIC third', request_id: SecureRandom.uuid)
    writer.call(input: third, id: original[:draft].id)
    replay = writer.call(input: second, id: original[:draft].id)
    expect(replay).to include(replayed: true, latest_revision: 3)
    expect(replay[:version].revision).to eq(2)
    expect(original[:draft].latest_version.name).to eq('SYNTHETIC third')
    expect(original[:draft].versions.count).to eq(3)
  end

  it 'reauthorizes an already-created writer and its idempotent receipts after eligibility revocation' do
    original = writer.call(input: input, unit_id: unit.id)
    JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false)
    expect { writer.call(input: input, unit_id: unit.id) }.to raise_error(Pundit::NotAuthorizedError)
    expect(original[:draft].versions.count).to eq(1)
  end

  it 'reauthorizes native role changes rather than caching administrator permissions' do
    original = writer.call(input: input, unit_id: unit.id)
    member.update!(custom_role: create(:custom_role, account: account, permissions: ['jrc_contact_center_view']))
    expect { writer.call(input: input, unit_id: unit.id) }.to raise_error(Pundit::NotAuthorizedError)
    expect(original[:draft].versions.count).to eq(1)
  end

  it 'rejects reuse after feature disablement or account suspension' do
    writer.call(input: input, unit_id: unit.id)
    account.disable_features!('jrc_contact_center')
    expect { writer.call(input: input, unit_id: unit.id) }.to raise_error(Pundit::NotAuthorizedError)
    account.enable_features!('jrc_contact_center')
    account.update!(status: :suspended)
    expect { writer.call(input: input, unit_id: unit.id) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'does not create an empty identity when a queue reference is invalid' do
    values[:definition] = { 'schema_version' => 1, 'start' => 'route', 'nodes' => [{ 'id' => 'route', 'type' => 'queue', 'queue_id' => '999999' }] }
    expect { writer.call(input: input, unit_id: unit.id) }.to raise_error(JrcContactCenter::OperationError, 'ivr_unavailable_queue')
    expect(JrcContactCenter::IvrDraft.where(account: account)).to be_empty
    expect(JrcContactCenter::IvrDraftVersion.where(account: account)).to be_empty
  end

  it 'does not grant access to another account unit or draft' do
    original = writer.call(input: input, unit_id: unit.id)
    other_account = create(:account)
    other_account.enable_features!('jrc_contact_center')
    other = create(:user, :contact_center_eligible, account: other_account, role: :administrator)
    other_context = { account: other_account, account_user: other_account.account_users.find_by!(user: other), user: other }
    other_writer = described_class.new(context: other_context)
    expect { other_writer.call(input: input, unit_id: unit.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { other_writer.call(input: input, id: original[:draft].id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(original[:draft].versions.count).to eq(1)
  end

  it 'allows archival of an unchanged historical definition after a destination is deactivated' do
    queue = JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'LOCAL', name: 'SYNTHETIC queue')
    values[:definition] = { 'schema_version' => 1, 'start' => 'route',
                            'nodes' => [{ 'id' => 'route', 'type' => 'queue', 'queue_id' => queue.id.to_s }] }
    original = writer.call(input: input, unit_id: unit.id)
    queue.update!(status: 'inactive')
    archive = JrcContactCenter::IvrDraftInput.new(**values, status: 'archived', expected_revision: 1, request_id: SecureRandom.uuid)
    result = writer.call(input: archive, id: original[:draft].id)
    expect(result[:version].status).to eq('archived')
    expect(result[:version].definition).to eq(original[:version].definition)
    restore = JrcContactCenter::IvrDraftInput.new(**values, expected_revision: 2, request_id: SecureRandom.uuid)
    expect { writer.call(input: restore, id: original[:draft].id) }.to raise_error(JrcContactCenter::OperationError, 'ivr_unavailable_queue')
    expect(original[:draft].latest_version.status).to eq('archived')
  end

  it 'does not use archival to bypass definition validation or rewrite content' do
    original = writer.call(input: input, unit_id: unit.id)
    archive = JrcContactCenter::IvrDraftInput.new(**values, status: 'archived', name: 'SYNTHETIC changed',
                                                            expected_revision: 1, request_id: SecureRandom.uuid)
    expect do
      writer.call(input: archive, id: original[:draft].id)
    end.to raise_error(JrcContactCenter::OperationError, 'ivr_archive_requires_unchanged_definition')
    expect(original[:draft].versions.count).to eq(1)
  end

  it 'cannot create a new identity already marked archived' do
    values[:status] = 'archived'
    expect do
      writer.call(input: input, unit_id: unit.id)
    end.to raise_error(JrcContactCenter::OperationError, 'ivr_archive_requires_unchanged_definition')
    expect(JrcContactCenter::IvrDraft.where(account: account)).to be_empty
  end

  it 'rolls back the identity and revision if the native audit persistence fails' do
    allow(Audited.audit_class).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Audited.audit_class.new))
    expect { writer.call(input: input, unit_id: unit.id) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(JrcContactCenter::IvrDraft.where(account: account)).to be_empty
    expect(JrcContactCenter::IvrDraftVersion.where(account: account)).to be_empty
  end
end
