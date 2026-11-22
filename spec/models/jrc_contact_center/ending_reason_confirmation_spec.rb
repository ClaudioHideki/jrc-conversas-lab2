require 'rails_helper'

RSpec.describe JrcContactCenter::EndingReasonConfirmation do
  include_context 'with a frozen ending reason catalogue'

  let(:ledger) do
    input = { attributes: { reason_code: entry.fetch('code') }, expected_revision: JrcContactCenter::QualificationDraftRevision.token(record),
              request_key: SecureRandom.uuid }
    JrcContactCenter::ConfirmEndingReason.new(account: account, member: member).call(record, **input)
    described_class.find_by!(account: account, source_qualification_id: record.id)
  end

  def guarded_sql(statement)
    described_class.transaction(requires_new: true) { described_class.connection.execute(statement) }
  end

  it 'derives account, actor, catalogue and source evidence in PostgreSQL instead of accepting a client provenance' do
    expect(ledger.actor_account_user_id).to eq(member.id)
    expect(ledger.actor_user_id).to eq(actor.id)
    expect(ledger.catalogue_id).to eq(session.reload.ending_reason_version_id)
    expect(ledger.payload.fetch('origin').fetch('qualification_id')).to eq(record.id)
    expect(ledger.integrity_sha256).to match(/\A[0-9a-f]{64}\z/)
    expect(ledger.payload.fetch('confirms_classification_only')).to be(true)
  end

  it 'rejects direct SQL edits of confirmed evidence even when ActiveRecord callbacks are bypassed' do
    original = ledger.attributes.deep_dup
    expect { guarded_sql("UPDATE #{described_class.table_name} SET reason_label='changed' WHERE id=#{ledger.id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /Ending reason confirmation is immutable/)
    expect(ledger.reload.attributes).to eq(original)
  end

  it 'rejects direct SQL deletion while the account is still live' do
    id = ledger.id
    expect { guarded_sql("DELETE FROM #{described_class.table_name} WHERE id=#{id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /Ending reason confirmation is immutable/)
    expect(described_class.exists?(id)).to be(true)
  end

  it 'prevents changing confirmed classification through direct qualification SQL as well as the API' do
    ledger
    expect { guarded_sql("UPDATE #{record.class.table_name} SET reason_code='other' WHERE id=#{record.id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /Confirmed ending reason cannot be changed/)
    expect(record.reload.reason_code).to eq(entry.fetch('code'))
    expect(record.completed_at).to be_nil
  end

  it 'rejects moving an immutable record across accounts' do
    other = create(:account)
    original = ledger.account_id
    expect { guarded_sql("UPDATE #{described_class.table_name} SET account_id=#{other.id} WHERE id=#{ledger.id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /Ending reason confirmation is immutable/)
    expect(ledger.reload.account_id).to eq(original)
  end

  it 'preserves the historical qualification identity when native qualification cleanup nullifies its live foreign key' do
    original = ledger.attributes.deep_dup
    guarded_sql("DELETE FROM #{record.class.table_name} WHERE id=#{record.id}")
    expect(ledger.reload.qualification_id).to be_nil
    expect(ledger.attributes.except('qualification_id')).to eq(original.except('qualification_id'))
    expect(ledger.source_qualification_id).to eq(record.id)
  end

  it 'does not allow manually severing a still-live qualification reference' do
    id = ledger.id
    expect { guarded_sql("UPDATE #{described_class.table_name} SET qualification_id=NULL WHERE id=#{id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /Ending reason confirmation is immutable/)
    expect(ledger.reload.qualification_id).to eq(record.id)
  end

  it 'adds no live actor foreign key that could erase history or block native user-membership lifecycle' do
    keys = described_class.connection.foreign_keys(described_class.table_name)
    expect(keys.map(&:to_table).sort).to eq(%w[accounts jrc_contact_center_ending_reason_versions jrc_contact_center_qualifications])
    expect(keys.find { |key| key.to_table == 'jrc_contact_center_qualifications' }.on_delete).to eq(:nullify)
    expect(keys.reject { |key| key.to_table == 'jrc_contact_center_qualifications' }.map(&:on_delete)).to all(eq(:cascade))
    expect(described_class.column_names).not_to include('updated_at')
  end

  it 'preserves the native account retirement block and the exact confirmation while attendance history still exists' do
    original = ledger.attributes.deep_dup
    expect do
      Account.transaction(requires_new: true) { account.destroy! }
    end.to raise_error(ActiveRecord::InvalidForeignKey, /jrc_contact_center_/)
    expect(Account.exists?(account.id)).to be(true)
    expect(ledger.reload.attributes).to eq(original)
    expect(record.class.exists?(record.id)).to be(true)
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to exist
  end
end
