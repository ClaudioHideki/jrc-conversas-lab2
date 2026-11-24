require 'rails_helper'
require Rails.root.join('db/migrate/20261124000000_create_contact_center_ending_action_executions')

# PRIVATE CANDIDATE. Regular rollbackable DDL fixtures in an owned test database.
RSpec.describe CreateContactCenterEndingActionExecutions do
  subject(:migration) { described_class.new }

  include_context 'with native ending execution original evidence'

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
end
