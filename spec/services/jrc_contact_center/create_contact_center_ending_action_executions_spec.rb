require 'rails_helper'
require Rails.root.join('db/migrate/20261124000000_create_contact_center_ending_action_executions')
require Rails.root.join('script/jrc_call_center_ending_origin_schema_probe')

# PRIVATE CANDIDATE. Regular rollbackable DDL fixtures in an owned test database.
RSpec.describe CreateContactCenterEndingActionExecutions do
  subject(:migration) { described_class.new }

  include_context 'with native ending execution original evidence'

  def trigger_kind_constraint(table, name)
    query = ApplicationRecord.sanitize_sql_array(
      ['SELECT pg_get_constraintdef(oid, true) FROM pg_constraint WHERE conrelid = ?::regclass AND conname = ?', table, name]
    )
    ApplicationRecord.connection.select_value(query)
  end

  def create_kind_probe(name, definition)
    connection = ApplicationRecord.connection
    config = ApplicationRecord.connection_db_config
    databases = %w[jrc_sd_bc_portal_concurrency_20261025_test jrc_cc_access_schema_reload_synthetic]
    owned = JrcContactCenter::SyntheticEndingOriginSchemaProbe.runner_owned? && config.configuration_hash[:host] == '127.0.0.1' &&
            databases.include?(config.database) && connection.current_database == config.database && connection.transaction_open?
    raise 'Rollbackable owned synthetic trigger-kind probe required' unless owned

    connection.execute(<<~SQL.squish)
      CREATE TEMP TABLE #{connection.quote_table_name(name)}
        (trigger_kind varchar(50) NOT NULL, CONSTRAINT cc_synthetic_ending_kind #{definition}) ON COMMIT DROP
    SQL
  end

  it 'verifies an identical schema without creating a task, activation, receipt or configuration version' do
    settings = account.reload.settings.deep_dup
    versions = JrcContactCenter::EndingActionVersion.where(account: account).pluck(:id)
    expect { migration.up }.not_to raise_error
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
    expect(account.reload.settings).to eq(settings)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).pluck(:id)).to eq(versions)
  end

  it 'refuses a missing owned immutable-success trigger instead of silently repairing the ledger' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute('DROP TRIGGER cc_ending_execution_immutable ON jrc_contact_center_ending_action_executions')
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected ending success ledger/)
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
  end

  it 'detects removal of the exact account-scoped original-evidence foreign key' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.remove_foreign_key(:jrc_contact_center_ending_action_executions, name: 'cc_ending_success_origin_fk')
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected ending success ledger/)
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
  end

  it 'rejects an unknown additional trigger rather than ignoring extra behavior on the owned ledger' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute(<<~SQL.squish)
          CREATE FUNCTION cc_synthetic_unreviewed_success() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$;
          CREATE TRIGGER cc_synthetic_unreviewed_success BEFORE INSERT ON jrc_contact_center_ending_action_executions
            FOR EACH ROW EXECUTE FUNCTION cc_synthetic_unreviewed_success();
        SQL
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected ending success ledger/)
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
  end

  it 'requires a separately reviewed rollback instead of removing successful destination history' do
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to exist
  end

  it 'preserves both native trigger kinds and rejects missing, unknown or altered values at the actual PostgreSQL check' do
    connection = ApplicationRecord.connection
    definition = trigger_kind_constraint('jrc_contact_center_ending_action_executions', 'cc_ending_success_trigger')
    create_kind_probe('cc_synthetic_success_kind_values', definition)
    %w[ending_reason_confirmation ending_action_completion].each do |value|
      connection.execute("INSERT INTO cc_synthetic_success_kind_values VALUES (#{connection.quote(value)})")
    end
    [nil, '', 'unknown', 'ENDING_ACTION_COMPLETION', 'ending_action_completion '].each do |value|
      expect do
        ApplicationRecord.transaction(requires_new: true) do
          connection.execute("INSERT INTO cc_synthetic_success_kind_values VALUES (#{connection.quote(value)})")
        end
      end.to raise_error(ActiveRecord::StatementInvalid)
    end
    expect(connection.select_value('SELECT count(*) FROM cc_synthetic_success_kind_values')).to eq(2)
  end

  it 'retains the exact typed trigger constraint after native PostgreSQL deparse and reparse without restamping its receipt' do
    definition = trigger_kind_constraint('jrc_contact_center_ending_action_executions', 'cc_ending_success_trigger')
    stored = ApplicationRecord.connection.table_comment('jrc_contact_center_ending_action_executions')
    create_kind_probe('cc_synthetic_success_kind_roundtrip', definition)
    copied = trigger_kind_constraint('pg_temp.cc_synthetic_success_kind_roundtrip', 'cc_synthetic_ending_kind')
    expect(copied).to eq(definition)
    expect { migration.up }.not_to raise_error
    expect(ApplicationRecord.connection.table_comment('jrc_contact_center_ending_action_executions')).to eq(stored)
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
  end
end
