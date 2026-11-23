require 'rails_helper'

RSpec.describe JrcContactCenter::EndingActionQueueScope do
  include_context 'with a native ending action queue scope'

  it 'records a native queue and its actual corporate scope without granting or activating an automation' do
    expect(scope.source_queue_id).to eq(queue.id)
    expect(scope.unit_id).to eq(unit.id)
    expect(scope.issuer_company_id).to eq(issuer.id)
    expect(scope.business_unit_id).to eq(business.id)
    expect(scope.scope_state).to eq('mapped')
    expect(scope.payload.slice('account_id', 'source_queue_id', 'unit_id')).to eq(
      'account_id' => account.id, 'source_queue_id' => queue.id, 'unit_id' => unit.id
    )
    expect(account.reload.settings.fetch('jrc_contact_center_acw', {})).not_to have_key('voice_ending_automations')
  end

  it 'preserves an unmapped scope without substituting a Group or company grant' do
    unit.update!(settings: {})
    current = scopes.last
    expect(current.scope_state).to eq('unmapped')
    expect([current.issuer_company_id, current.business_unit_id]).to eq([nil, nil])
    expect(current.payload.fetch('scope_reason')).to eq('unmapped')
  end

  it 'does not copy unrelated settings, credentials or configuration text into its immutable payload' do
    original = scope.attributes.deep_dup
    unit.update!(settings: unit.settings.merge('synthetic_secret' => 'SYNTHETIC never copy this value'))
    expect(scopes.count).to eq(1)
    expect(scope.reload.attributes).to eq(original)
    expect(scope.payload.to_json).not_to include('synthetic_secret', 'SYNTHETIC never copy this value')
  end

  it 'does not append duplicate evidence on an unchanged capture' do
    original = scope.attributes.deep_dup
    id = ApplicationRecord.connection.select_value("SELECT cc_ending_action_capture_queue_scope(#{queue.id})")
    expect(id).to eq(scope.id)
    expect(scopes.count).to eq(1)
    expect(scope.reload.attributes).to eq(original)
  end

  it 'rejects editing immutable evidence through SQL that bypasses ActiveRecord callbacks' do
    original = scope.attributes.deep_dup
    expect { guarded_ending_scope_sql("UPDATE #{described_class.table_name} SET scope_state='unmapped' WHERE id=#{scope.id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /queue scope history is immutable/)
    expect(scope.reload.attributes).to eq(original)
  end

  it 'rejects deleting immutable evidence while the account is live' do
    id = scope.id
    expect { guarded_ending_scope_sql("DELETE FROM #{described_class.table_name} WHERE id=#{id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /queue scope history is immutable/)
    expect(described_class.exists?(id)).to be(true)
  end

  it 'does not let an insert substitute another account for the native queue account' do
    other = create(:account)
    expect do
      guarded_ending_scope_sql("INSERT INTO #{described_class.table_name}(account_id,source_queue_id) VALUES(#{other.id},#{queue.id})")
    end.to raise_error(ActiveRecord::StatementInvalid, /queue identity mismatch/)
    expect(described_class.where(account: other)).to be_empty
  end

  it 'does not accept a client timestamp as provenance' do
    scope
    sql = <<~SQL.squish
      INSERT INTO #{described_class.table_name}(account_id,source_queue_id,created_at)
      VALUES(#{account.id},#{queue.id},'2020-01-01')
    SQL
    expect { guarded_ending_scope_sql(sql) }.to raise_error(ActiveRecord::StatementInvalid, /provenance is server generated/)
    expect(scopes.count).to eq(1)
  end

  it 'rejects manually severing the reference to a still-live native queue' do
    id = scope.id
    expect { guarded_ending_scope_sql("UPDATE #{described_class.table_name} SET queue_id=NULL WHERE id=#{id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /queue scope history is immutable/)
    expect(scope.reload.queue_id).to eq(queue.id)
  end

  it 'allows only native queue cleanup to nullify the live reference while preserving exact history' do
    original = scope.attributes.deep_dup
    guarded_ending_scope_sql("DELETE FROM jrc_contact_center_queues WHERE id=#{queue.id}")
    expect(scope.reload.queue_id).to be_nil
    expect(scope.attributes.except('queue_id')).to eq(original.except('queue_id'))
    expect(scope.source_queue_id).to eq(queue.id)
  end

  it 'adds no live corporate or user foreign key that could erase old scope identities' do
    keys = described_class.connection.foreign_keys(described_class.table_name)
    expect(keys.map(&:to_table).sort).to eq(%w[accounts jrc_contact_center_queues])
    expect(keys.find { |key| key.to_table == 'jrc_contact_center_queues' }.on_delete).to eq(:nullify)
    expect(described_class.column_names).not_to include('updated_at', 'actor_user_id')
  end

  it 'uses only positive canonical bigint identities instead of coercing malformed JSON values' do
    values = [nil, false, true, '', '01', 0, -1, 1.5, {}, [], '9223372036854775808', 1, '9223372036854775807']
    connection = ApplicationRecord.connection
    actual = values.map do |value|
      connection.select_value("SELECT cc_ending_action_scope_id(#{connection.quote(value.to_json)}::jsonb)")
    end
    expect(actual).to eq([nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 1, 9_223_372_036_854_775_807])
  end

  it 'leaves pre-anchor events unattested instead of inferring a historical mapping' do
    original = scope
    connection = ApplicationRecord.connection
    timestamp = connection.quote(original.created_at - Rational(1, 1_000_000))
    actual = connection.select_value("SELECT cc_ending_action_queue_scope_at(#{account.id},#{queue.id},#{timestamp}::timestamp)")
    expect(actual).to be_nil
    expect(scopes.count).to eq(1)
  end

  it 'selects the recorded scope effective at the observation time rather than the current mapping' do
    original = scope
    unit.update!(settings: {})
    connection = ApplicationRecord.connection
    timestamp = connection.quote(original.created_at)
    actual = connection.select_value("SELECT cc_ending_action_queue_scope_at(#{account.id},#{queue.id},#{timestamp}::timestamp)")
    expect(actual).to eq(original.id)
    expect(scopes.last.scope_state).to eq('unmapped')
  end

  it 'never resolves a native queue scope by supplying another account to the historical lookup' do
    original = scope
    other = create(:account)
    timestamp = ApplicationRecord.connection.quote(original.created_at)
    actual = ApplicationRecord.connection.select_value("SELECT cc_ending_action_queue_scope_at(#{other.id},#{queue.id},#{timestamp}::timestamp)")
    expect(actual).to be_nil
    expect(scopes.count).to eq(1)
  end
end
