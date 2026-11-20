require 'rails_helper'

RSpec.describe JrcContactCenter::EndingReasonVersion do
  include_context 'with a frozen ending reason catalogue'

  it 'records exact audit provenance and a database digest without creating another catalogue or grant' do
    version = described_class.where(account: account).sole
    audit = Audited.audit_class.find(version.source_audit_id)
    expect(version.definition).to eq(JrcContactCenter::AcwEndingReasons.new(account: account).call)
    expect(version.created_at).to eq(audit.created_at)
    expect(version.actor_user_id).to eq(actor.id)
    expect(version.integrity_sha256).to match(/\A[0-9a-f]{64}\z/)
    expect(version.options).to eq([entry.slice('code', 'name')])
    expect(version.inspect).not_to include(entry.fetch('name'))
  end

  it 'rolls back settings and the native audit if the history cannot be preserved' do
    previous = account.reload.settings.deep_dup
    audit_count = Audited.audit_class.where(associated: account).count
    allow(described_class).to receive(:record_change!).and_raise(ActiveRecord::RecordInvalid)
    expect { configure_ending_reasons!(entries: [entry.merge('name' => 'SYNTHETIC changed')]) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(account.reload.settings).to eq(previous)
    expect(Audited.audit_class.where(associated: account).count).to eq(audit_count)
    expect(described_class.where(account: account).count).to eq(1)
  end

  it 'preserves old active names and codes after renaming or deactivating the next version' do
    first = described_class.where(account: account).sole
    configure_ending_reasons!(entries: [entry.merge('name' => 'SYNTHETIC next', 'active' => false)], queues: [])
    expect(first.reload.options).to eq([entry.slice('code', 'name')])
    expect(described_class.where(account: account).order(:revision).pluck(:revision)).to eq([1, 2])
    expect(described_class.where(account: account).order(:revision).last.options).to be_empty
  end

  it 'rejects direct SQL mutation without relying on the immutable model concern' do
    version = described_class.where(account: account).sole
    expect do
      described_class.transaction(requires_new: true) do
        described_class.connection.execute("UPDATE #{described_class.table_name} SET definition = '{}'::jsonb WHERE id = #{version.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /Ending reason versions are immutable/)
    expect(version.reload.definition.fetch('version')).to eq(1)
  end

  it 'does not accept another accounts audit as provenance for a forged version' do
    version = described_class.where(account: account).sole
    foreign = create(:account)
    expect do
      described_class.transaction(requires_new: true) do
        described_class.connection.execute("INSERT INTO #{described_class.table_name} (account_id, revision, source_audit_id, definition) " \
                                           "SELECT #{foreign.id}, 1, source_audit_id, definition FROM #{described_class.table_name} " \
                                           "WHERE id = #{version.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /Ending reason audit provenance unavailable/)
    expect(described_class.where(account: foreign)).to be_empty
  end

  it 'retains the immutable definition and actor primitives if native audit retention removes its source row later' do
    version = described_class.where(account: account).sole
    original = version.attributes
    Audited.audit_class.where(id: version.source_audit_id).delete_all
    expect(version.reload.attributes).to eq(original)
    expect(version.options).to eq([entry.slice('code', 'name')])
  end

  it 'rejects NULL audit identities rather than letting PostgreSQL three-valued comparisons bypass provenance' do
    version = described_class.where(account: account).sole
    foreign = create(:account)
    source = Audited.audit_class.find(version.source_audit_id)
    table = Audited.audit_class.connection.quote_table_name(Audited.audit_class.table_name)
    audit_id = Audited.audit_class.connection.select_value(
      "INSERT INTO #{table} (audited_changes, action, comment, created_at) " \
      "SELECT audited_changes, action, comment, created_at FROM #{table} WHERE id = #{source.id} RETURNING id"
    )
    expect do
      described_class.transaction(requires_new: true) do
        definition = described_class.connection.quote(version.definition.to_json)
        described_class.connection.execute("INSERT INTO #{described_class.table_name} (account_id, revision, source_audit_id, definition) " \
                                           "VALUES (#{foreign.id}, 1, #{audit_id}, #{definition}::jsonb)")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /Ending reason audit provenance unavailable/)
    expect(described_class.where(account: foreign)).to be_empty
  end

  it 'preserves the native account retirement block while attendance evidence still exists' do
    id = account.id
    record
    expect do
      Account.transaction(requires_new: true) { account.destroy! }
    end.to raise_error(ActiveRecord::InvalidForeignKey, /jrc_contact_center_/)
    expect(Account.exists?(id)).to be(true)
    expect(described_class.where(account_id: id).count).to eq(1)
    expect(JrcContactCenter::CallSession.exists?(session.id)).to be(true)
  end

  it 'does not leave an orphaned catalogue when an otherwise unreferenced native account is retired' do
    other = create(:account)
    other_policy = JrcContactCenter::AcwPolicy.new(account: other)
    other_policy.update!({ voice: 180, whatsapp: 180 }, voice_reason_catalog: [entry], expected_revision: other_policy.revision)
    id = other.id
    expect(described_class.where(account_id: id).count).to eq(1)
    other.delete
    expect(Account.exists?(id)).to be(false)
    expect(described_class.where(account_id: id)).to be_empty
  end
end
