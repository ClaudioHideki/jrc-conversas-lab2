# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261008180000_extend_jrc_nico_helpdesk_delivery').to_s

# Serial PostgreSQL schema tests on the disposable R345 clone only; no transport or shared database.
RSpec.describe ExtendJrcNicoHelpdeskDelivery, type: :model do
  include_context 'JRC Service Desk domain'

  let(:receipt_model) { JrcNico::Helpdesk::DeliveryReceipt }
  let(:legacy_column_snapshot) { column_snapshot }
  let(:policy) do
    definition = JrcNico::Helpdesk::Definition.defaults
    JrcNico::Helpdesk::PolicyVersion.create!(
      account: sd_account, author: sd_account_user, number: 1, state: 'draft', enabled: false,
      definition: definition, digest: JrcNico::Helpdesk::Definition.digest(definition)
    )
  end

  prepend_before do
    connection = ActiveRecord::Base.connection
    allowed = %w[jrc_rel_sd_r345_preservation_test jrc_rel_sd_r345_r3_retry_test]
    raise 'R5 schema tests require Rails test environment' unless Rails.env.test?
    raise 'R5 schema tests require actual PostgreSQL' unless connection.adapter_name == 'PostgreSQL'

    database = connection.select_value('SELECT current_database()')
    unless allowed.include?(database) && ENV.fetch('POSTGRES_DATABASE', nil) == database
      raise 'R5 schema tests require the exact configured disposable database allowlist'
    end

    legacy_column_snapshot
  end

  def column_snapshot
    legacy_columns = receipt_model.connection.columns(receipt_model.table_name).reject do |column|
      described_class::NEW_COLUMNS.include?(column.name.to_sym)
    end
    legacy_columns.map { |column| [column.name, column.sql_type, column.null, column.default] }
  end

  def receipt_fields(state = 'pending')
    source = JrcNico::Helpdesk::Event.create!(
      account: sd_account, actor: sd_account_user, policy_version: policy, ticket: sd_ticket,
      rule_key: 'R01', correlation_key: SecureRandom.uuid, detected_at: Time.current
    )
    now = Time.current.change(usec: 123_456)
    { account_id: sd_account.id, recipient_id: sd_account_user.id, source_type: 'event', source_id: source.id,
      channel: 'nico', state: state, delivered_at: state == 'delivered' ? now : nil,
      attempted_at: now - 1.second, reason: 'historical_fixture', remote_id: 'native-reference',
      created_at: now - 1.hour, updated_at: now }
  end

  def dispatch_fields(state = 'dispatching')
    receipt_fields(state).merge(
      claim_token: SecureRandom.uuid, attempt_number: 1, payload_digest: 'a' * 64, routing_digest: 'b' * 64,
      dispatching_at: Time.current, sent_at: state == 'sent' ? Time.current : nil
    )
  end

  def raw_insert(fields)
    connection = receipt_model.connection
    columns = fields.keys.map { |key| connection.quote_column_name(key) }.join(', ')
    placeholders = fields.keys.each_index.map { |index| "$#{index + 1}" }.join(', ')
    bindings = fields.map do |key, value|
      ActiveRecord::Relation::QueryAttribute.new(key.to_s, value, receipt_model.type_for_attribute(key.to_s))
    end
    sql = "INSERT INTO #{connection.quote_table_name(receipt_model.table_name)} (#{columns}) VALUES (#{placeholders}) RETURNING id"
    receipt_model.transaction(requires_new: true) { connection.exec_query(sql, 'R5 receipt database constraint fixture', bindings) }
  end

  def persisted_rows(ids, columns)
    receipt_model.where(id: ids).order(:id).map { |row| row.attributes.slice(*columns) }
  end

  it 'requires actual PostgreSQL and retains the original unique receipt index' do
    expect(receipt_model.connection.adapter_name).to eq('PostgreSQL')
    index = receipt_model.connection.indexes(receipt_model.table_name).find { |item| item.name == 'nico_hd_delivery_once' }
    expect(index.unique).to be(true)
    expect(index.columns).to eq(%w[account_id recipient_id source_type source_id channel])
  end

  it 'preserves every legacy state and original timestamp/value through actual down and up without backfill' do
    ids = %w[pending delivered failed blocked unknown].map { |state| raw_insert(receipt_fields(state)).rows.first.first }
    legacy_columns = receipt_model.column_names - described_class::NEW_COLUMNS.map(&:to_s)
    before = persisted_rows(ids, legacy_columns)
    migration = described_class.new
    begin
      migration.down
      receipt_model.reset_column_information
      expect(column_snapshot).to eq(legacy_column_snapshot)
      expect(persisted_rows(ids, legacy_columns)).to eq(before)
      migration.up
      receipt_model.reset_column_information
      expect(column_snapshot).to eq(legacy_column_snapshot)
      expect(persisted_rows(ids, legacy_columns)).to eq(before)
      extensions = receipt_model.where(id: ids).pluck(*described_class::NEW_COLUMNS)
      expect(extensions).to eq(Array.new(5) { [nil, 0, nil, nil, nil, nil, {}] })
    ensure
      migration.up unless migration.column_exists?(described_class::TABLE, :claim_token)
      receipt_model.reset_column_information
    end
  end

  {
    'an unsupported state' => [{ state: 'accepted' }, 'nico_hd_receipt_state'],
    'a negative attempt number' => [{ attempt_number: -1 }, 'nico_hd_receipt_attempt'],
    'a delivered state with no delivery timestamp' => [{ state: 'delivered' }, 'nico_hd_receipt_delivered'],
    'a timestamp claiming delivery for an unknown result' => [{ state: 'unknown', delivered_at: Time.utc(2026, 10, 8) },
                                                              'nico_hd_receipt_delivered'],
    'a sent timestamp on a merely pending receipt' => [{ sent_at: Time.utc(2026, 10, 8) }, 'nico_hd_receipt_sent'],
    'an invalid payload digest' => [{ payload_digest: 'not-a-sha' }, 'nico_hd_receipt_payload_digest'],
    'an invalid routing digest' => [{ routing_digest: 'C' * 64 }, 'nico_hd_receipt_routing_digest'],
    'a claim with no positive attempt' => [{ claim_token: '4a9f89c0-792c-446a-9d7b-a59db84d07b5' }, 'nico_hd_receipt_claim']
  }.each do |description, (overrides, constraint)|
    it "rejects #{description} independently of model validation" do
      expect { raw_insert(receipt_fields.merge(overrides)) }.to raise_error(ActiveRecord::StatementInvalid, /#{constraint}/)
    end
  end

  it 'rejects sent without its acceptance timestamp independently of model validation' do
    expect { raw_insert(dispatch_fields('sent').merge(sent_at: nil)) }.to raise_error(ActiveRecord::StatementInvalid, /nico_hd_receipt_sent/)
  end

  %i[claim_token dispatching_at attempted_at payload_digest routing_digest].each do |field|
    it "rejects dispatching without #{field} independently of model validation" do
      expect { raw_insert(dispatch_fields.merge(field => nil)) }.to raise_error(ActiveRecord::StatementInvalid, /nico_hd_receipt_dispatch/)
    end
  end

  %w[dispatching sent].each do |state|
    it "persists #{state} with a complete committed-claim shape and refuses destructive down" do
      id = raw_insert(dispatch_fields(state)).rows.first.first
      before = receipt_model.find(id).attributes
      expect { described_class.new.down }.to raise_error(ActiveRecord::IrreversibleMigration, /contain evidence/)
      expect(receipt_model.find(id).attributes).to eq(before)
    end
  end

  it 'refuses down when an uncertain result retains durable claim evidence' do
    id = raw_insert(dispatch_fields.merge(state: 'unknown')).rows.first.first
    before = receipt_model.find(id).attributes
    expect { described_class.new.down }.to raise_error(ActiveRecord::IrreversibleMigration, /contain evidence/)
    expect(receipt_model.find(id).attributes).to eq(before)
  end

  it 'refuses down if a receipt contains only additional sanitized evidence' do
    id = raw_insert(receipt_fields.merge(evidence: { 'adapter' => 'action_mailer_test' })).rows.first.first
    before = receipt_model.find(id).attributes
    expect { described_class.new.down }.to raise_error(ActiveRecord::IrreversibleMigration, /contain evidence/)
    expect(receipt_model.find(id).attributes).to eq(before)
  end

  it 'still rejects duplicate delivery identity at the original database index' do
    fields = receipt_fields
    raw_insert(fields)
    expect { raw_insert(fields) }.to raise_error(ActiveRecord::RecordNotUnique, /nico_hd_delivery_once/)
  end
end
