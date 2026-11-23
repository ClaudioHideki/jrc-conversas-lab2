require 'rails_helper'

# Prepared, not executed. Classification evidence is not an operational effect receipt.
RSpec.describe JrcContactCenter::EndingActionCompletion do
  include_context 'with native ending execution original evidence'

  it 'does not record a completion while actual native ACW remains pending' do
    origin
    expect(qualification.reload.completed_at).to be_nil
    expect(described_class.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'refuses a fabricated completion before the original native qualification actually completes' do
    original = origin
    expect do
      guarded_origin_sql("INSERT INTO #{described_class.table_name}(account_id,origin_id) VALUES(#{account.id},#{original.id})")
    end.to raise_error(ActiveRecord::StatementInvalid, /Ending action native completion unavailable/)
    expect(described_class.where(account: account)).to be_empty
    expect(qualification.reload.completed_at).to be_nil
  end

  it 'retains native mandatory result validation and does not record a partial completion on failure' do
    origin
    expect do
      JrcContactCenter::QualificationManager.new(account: account, member: member).complete!(
        qualification, { reason_code: 'SYNTHETIC_ORIGIN_REASON' }
      )
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(qualification.reload.completed_at).to be_nil
    expect(described_class.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'matches the immutable evidence against the actual completed native classification' do
    original = origin
    complete_origin_qualification
    receipt = described_class.find_by!(account: account, origin: original)
    proof = described_class.connection.select_value("SELECT cc_ending_action_completion_matches(#{original.id},#{qualification.id})")
    expect(proof).to be(true)
    expect(receipt.payload.fetch('source_qualification_id')).to eq(qualification.id)
    expect(receipt.payload.fetch('actor_user_id')).to eq(actor.id)
    expect(receipt.payload.fetch('rule_version_id')).to eq(original.version_id)
    expect(receipt.integrity_sha256).to match(/\A[0-9a-f]{64}\z/)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'rejects a completion transplanted to another account' do
    original = origin
    complete_origin_qualification
    other = create(:account)
    expect do
      guarded_origin_sql("INSERT INTO #{described_class.table_name}(account_id,origin_id) VALUES(#{other.id},#{original.id})")
    end.to raise_error(ActiveRecord::StatementInvalid, /Ending action completion origin unavailable/)
    expect(described_class.where(account: other)).to be_empty
    expect(described_class.where(account: account).count).to eq(1)
  end

  it 'rejects direct SQL editing of an attested completion while preserving its exact source' do
    original = origin
    complete_origin_qualification
    receipt = described_class.find_by!(account: account, origin: original)
    first = receipt.attributes.deep_dup
    expect { guarded_origin_sql("UPDATE #{described_class.table_name} SET outcome_code='changed' WHERE id=#{receipt.id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /Ending action completion evidence is immutable/)
    expect(receipt.reload.attributes).to eq(first)
  end

  it 'rejects direct SQL deletion of the native completion evidence while the account exists' do
    original = origin
    complete_origin_qualification
    receipt = described_class.find_by!(account: account, origin: original)
    expect { guarded_origin_sql("DELETE FROM #{described_class.table_name} WHERE id=#{receipt.id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /Ending action completion evidence is immutable/)
    expect(described_class.exists?(receipt.id)).to be(true)
  end

  it 'preserves historical evidence after native qualification cleanup but never treats that missing source as executable' do
    original = origin
    complete_origin_qualification
    receipt = described_class.find_by!(account: account, origin: original)
    first = receipt.attributes.deep_dup
    guarded_origin_sql("DELETE FROM jrc_contact_center_qualifications WHERE id=#{qualification.id}")
    expect(receipt.reload.attributes).to eq(first)
    expect(original.reload.qualification_id).to be_nil
    proof = described_class.connection.select_value("SELECT cc_ending_action_completion_matches(#{original.id},#{qualification.id})")
    expect(proof).to be(false)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end
end
