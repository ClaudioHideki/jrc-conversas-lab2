require 'rails_helper'

RSpec.describe JrcContactCenter::EndingActionReadiness do
  include_context 'with native ending execution original evidence'

  let(:readiness) do
    JrcContactCenter::EndingActions::ActivateRule.new(account: account, member: member, rule_code: 'SYNTHETIC_ORIGIN_RULE',
                                                       request_key: SecureRandom.uuid,
                                                       expected_revision: JrcContactCenter::AcwPolicy.new(account: account).revision).call
  end

  it 'rejects direct SQL retargeting and preserves the complete original activation' do
    original = readiness.attributes.deep_dup
    expect { guarded_origin_sql("UPDATE #{described_class.table_name} SET source_timezone='UTC' WHERE id=#{readiness.id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /Ending execution readiness is immutable/)
    expect(readiness.reload.attributes).to eq(original)
  end

  it 'rejects direct SQL deletion while the actual account is live' do
    identifier = readiness.id
    expect { guarded_origin_sql("DELETE FROM #{described_class.table_name} WHERE id=#{identifier}") }
      .to raise_error(ActiveRecord::StatementInvalid, /Ending execution readiness is immutable/)
    expect(described_class.exists?(identifier)).to be(true)
  end

  it 'rejects supplied evidence instead of trusting a caller timestamp, actor user or lower high-water mark' do
    version = JrcContactCenter::EndingActionVersion.where(account: account).sole
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        described_class.create!(account: account, version: version, actor_account_user_id: member.id, actor_user_id: actor.id,
                                rule_code: 'SYNTHETIC_ORIGIN_RULE', request_key: SecureRandom.uuid, cutoff_call_id: 0)
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /readiness evidence is server generated/)
    expect(described_class.where(account: account)).to be_empty
  end

  it 'rejects another accounts version even when all referenced integer identities are known' do
    version = JrcContactCenter::EndingActionVersion.where(account: account).sole
    other = create(:account)
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        described_class.create!(account: other, version: version, actor_account_user_id: member.id,
                                rule_code: 'SYNTHETIC_ORIGIN_RULE', request_key: SecureRandom.uuid)
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /Current ending rule version required/)
    expect(described_class.where(account: other)).to be_empty
  end
end
