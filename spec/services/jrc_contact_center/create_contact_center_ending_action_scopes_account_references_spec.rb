require 'rails_helper'
require Rails.root.join('db/migrate/20261123034500_create_contact_center_ending_action_scopes')
require Rails.root.join('lib/jrc_contact_center/ending_action_scope_schema_receipt')

RSpec.describe CreateContactCenterEndingActionScopes do
  include_context 'with a native ending action queue scope'

  let(:reference_table) { JrcContactCenter::EndingActionScopeSchemaReceipt::ACCOUNT_TABLE }
  let(:connection) { ApplicationRecord.connection }

  it 'uses only the real account identity without duplicating accounts, people or operational configuration' do
    scope
    before = [Account.count, User.count, queue.attributes.deep_dup, unit.attributes.deep_dup]
    expect(connection.select_values("SELECT account_id FROM #{reference_table} WHERE account_id=#{account.id}")).to eq([account.id])
    expect(connection.columns(reference_table).map(&:name)).to eq(['account_id'])
    expect(connection.columns(reference_table).sole.default_function).to be_nil
    expect([Account.count, User.count, queue.reload.attributes, unit.reload.attributes]).to eq(before)
  end

  it 'creates exactly one technical reference when a real new account is inserted' do
    other = create(:account)
    expect(connection.select_values("SELECT account_id FROM #{reference_table} WHERE account_id=#{other.id}")).to eq([other.id])
    expect(Account.find(other.id)).to eq(other)
  end

  it 'rejects a reference without a real account instead of admitting an orphaned history root' do
    account
    missing = Account.maximum(:id) + 1000
    expect { guarded_ending_scope_sql("INSERT INTO #{reference_table}(account_id) VALUES(#{missing})") }
      .to raise_error(ActiveRecord::InvalidForeignKey)
    expect(connection.select_value("SELECT count(*) FROM #{reference_table} WHERE account_id=#{missing}")).to eq(0)
  end

  it 'rejects removing the technical root while its real account is live and preserves every scope row' do
    original = scope.attributes.deep_dup
    expect { guarded_ending_scope_sql("DELETE FROM #{reference_table} WHERE account_id=#{account.id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /account reference is immutable/)
    expect(scope.reload.attributes).to eq(original)
  end

  it 'rejects reparenting the root to another real account without changing either history' do
    original = scope.attributes.deep_dup
    other = create(:account)
    expect { guarded_ending_scope_sql("UPDATE #{reference_table} SET account_id=#{other.id} WHERE account_id=#{account.id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /account reference is immutable/)
    expect(scope.reload.attributes).to eq(original)
    sql = "SELECT account_id FROM #{reference_table} WHERE account_id IN (#{account.id},#{other.id}) ORDER BY account_id"
    expect(connection.select_values(sql)).to eq([account.id, other.id].sort)
  end

  it 'cascades the new reference and history only after actual root deletion and leaves another account intact' do
    original = scope.attributes.deep_dup
    other = create(:account)
    other_unit = JrcContactCenter::Unit.create!(account: other, code: 'SYNTHETIC', name: 'SYNTHETIC empty retirement', kind: 'sac')
    other_queue = JrcContactCenter::Queue.create!(account: other, unit: other_unit, code: 'SYNTHETIC', name: 'SYNTHETIC empty retirement',
                                                service_kind: 'voice', strategy: 'ring_all')
    expect(JrcContactCenter::EndingActionQueueScope.where(account: other, source_queue_id: other_queue.id)).to exist
    guarded_ending_scope_sql("DELETE FROM accounts WHERE id=#{other.id}")
    expect(Account.exists?(other.id)).to be(false)
    expect(connection.select_value("SELECT count(*) FROM #{reference_table} WHERE account_id=#{other.id}")).to eq(0)
    expect(JrcContactCenter::EndingActionQueueScope.where(account_id: other.id)).to be_empty
    expect(scope.reload.attributes).to eq(original)
  end
end
