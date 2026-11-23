require 'rails_helper'

# Prepared, not executed. Real PostgreSQL, native audit and current account records are required.
RSpec.describe JrcContactCenter::EndingActionVersion do
  include_context 'with native private ending action definitions'

  it 'records exact native audit and actor provenance without creating a destination or granting a capability' do
    before = [JrcProjects::Task.count, JrcContactCenter::AccessGrant.count]
    version = record_private_ending_definition
    audit = Audited.audit_class.find(version.source_audit_id)
    expect(version.definition).to eq(definition)
    expect(version.actor_user_id).to eq(actor.id)
    expect(version.created_at).to be >= audit.created_at
    expect(version.definition_sha256).to match(/\A[0-9a-f]{64}\z/)
    expect(version.integrity_sha256).to match(/\A[0-9a-f]{64}\z/)
    expect(catalogue.head).to eq('version' => 1, 'nonce' => version.head_nonce)
    expect([JrcProjects::Task.count, JrcContactCenter::AccessGrant.count]).to eq(before)
  end

  it 'preserves earlier immutable definitions and current head across actual version increments' do
    first = record_private_ending_definition
    original = first.attributes.deep_dup
    second = record_private_ending_definition('version' => 2, 'entries' => [])
    expect(versions.pluck(:revision)).to eq([1, 2])
    expect(first.reload.attributes).to eq(original)
    expect(second.created_at).to be > first.created_at
    expect(second.head_nonce).not_to eq(first.head_nonce)
    expect(catalogue.call).to eq('version' => 2, 'entries' => [])
    expect { catalogue.verify_synchronized! }.not_to raise_error
  end

  it 'rejects direct SQL mutation and deletion without depending on an immutable model callback' do
    version = record_private_ending_definition
    original = version.attributes.deep_dup
    expect { guarded_ending_version_sql("UPDATE #{described_class.table_name} SET revision=2 WHERE id=#{version.id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /Ending action versions are immutable/)
    expect { guarded_ending_version_sql("DELETE FROM #{described_class.table_name} WHERE id=#{version.id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /Ending action versions are immutable/)
    expect(version.reload.attributes).to eq(original)
  end

  it 'rejects the reuse of another accounts audit without creating a foreign version' do
    original = record_private_ending_definition
    other = create(:account)
    statement = <<~SQL.squish
      INSERT INTO #{described_class.table_name} (account_id, revision, source_audit_id, head_nonce, private_definition)
      SELECT #{other.id},revision,source_audit_id,head_nonce,private_definition
      FROM #{described_class.table_name} WHERE id=#{original.id}
    SQL
    expect { guarded_ending_version_sql(statement) }
      .to raise_error(ActiveRecord::StatementInvalid, /Ending action private definition head mismatch/)
    expect(described_class.where(account: other)).to be_empty
    expect(versions.count).to eq(1)
  end

  it 'rejects an unaudited head change and restores the account settings atomically on failure' do
    first = record_private_ending_definition
    original = account.reload.settings.deep_dup
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        head = catalogue.head_for('version' => 2, 'entries' => [])
        policy = account.settings.fetch(JrcContactCenter::AcwPolicy::KEY).merge(catalogue.class::KEY => head)
        account.update!(settings: account.settings.merge(JrcContactCenter::AcwPolicy::KEY => policy))
        described_class.create!(account: account, revision: 2, head_nonce: head.fetch('nonce'),
                                definition: { 'version' => 2, 'entries' => [] }, source_audit_id: first.source_audit_id)
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /Ending action audit provenance unavailable/)
    expect(account.reload.settings).to eq(original)
    expect(versions.pluck(:revision)).to eq([1])
  end

  it 'fails closed when a public head is missing, malformed or does not identify the latest private history' do
    first = record_private_ending_definition
    original = account.settings.deep_dup
    [nil, false, { 'version' => 1, 'nonce' => SecureRandom.uuid }].each do |head|
      policy = original.fetch(JrcContactCenter::AcwPolicy::KEY).merge(catalogue.class::KEY => head)
      account.settings = original.merge(JrcContactCenter::AcwPolicy::KEY => policy)
      expect { catalogue.verify_synchronized! }.to raise_error(JrcContactCenter::OperationError, 'ending_automation_ledger_unavailable')
    end
    account.reload
    expect(catalogue.head.fetch('nonce')).to eq(first.head_nonce)
  end

  it 'retains private history and primitive actor provenance after native audit retention removes the source row' do
    version = record_private_ending_definition
    original = version.attributes.deep_dup
    Audited.audit_class.where(id: version.source_audit_id).delete_all
    expect(version.reload.attributes).to eq(original)
    expect(catalogue.call).to eq(definition)
    expect { catalogue.verify_synchronized! }.not_to raise_error
  end

  it 'rejects a duplicate version instead of reusing its nonce or overwriting private history' do
    first = record_private_ending_definition
    original = account.reload.settings.deep_dup
    audit_count = Audited.audit_class.where(associated: account).count
    expect { record_private_ending_definition }.to raise_error(ActiveRecord::StatementInvalid, /Ending action definition sequence conflict/)
    expect(account.reload.settings).to eq(original)
    expect(Audited.audit_class.where(associated: account).count).to eq(audit_count)
    expect(versions.pluck(:id)).to eq([first.id])
  end

  it 'rejects an actual nonce collision with a static error before a uniqueness failure can include a private failed row' do
    first = record_private_ending_definition
    original = account.reload.settings.deep_dup
    audit_count = Audited.audit_class.where(associated: account).count
    allow(catalogue).to receive(:head_for).and_return('version' => 2, 'nonce' => first.head_nonce)
    expect { record_private_ending_definition('version' => 2, 'entries' => []) }
      .to raise_error(ActiveRecord::StatementInvalid, /Ending action definition head already used/)
    expect(account.reload.settings).to eq(original)
    expect(Audited.audit_class.where(associated: account).count).to eq(audit_count)
    expect(versions.pluck(:id)).to eq([first.id])
  end
end
