require 'rails_helper'
require Rails.root.join('db/migrate/20261123235000_create_contact_center_ending_action_readinesses')

RSpec.describe CreateContactCenterEndingActionReadinesses do
  subject(:migration) { described_class.new }

  include_context 'with native ending execution original evidence'

  it 'verifies an identical installed schema without arming a rule or changing configuration history' do
    settings = account.reload.settings.deep_dup
    versions = JrcContactCenter::EndingActionVersion.where(account: account).pluck(:id)
    expect { migration.up }.not_to raise_error
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
    expect(account.reload.settings).to eq(settings)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).pluck(:id)).to eq(versions)
  end

  it 'refuses a missing owned immutability trigger instead of silently repairing an unproven ledger' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute('DROP TRIGGER cc_ending_action_readiness_immutable ON jrc_contact_center_ending_action_readinesses')
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected ending readiness schema/)
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
  end

  it 'detects removal of the exact account-scoped version foreign key' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.remove_foreign_key(:jrc_contact_center_ending_action_readinesses, name: 'cc_ending_readiness_version_fk')
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected ending readiness schema/)
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
  end

  it 'rejects an unknown extra trigger instead of ignoring unreviewed behavior on its owned ledger' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute(<<~SQL.squish)
          CREATE FUNCTION cc_synthetic_unreviewed_readiness() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$;
          CREATE TRIGGER cc_synthetic_unreviewed_readiness BEFORE INSERT ON jrc_contact_center_ending_action_readinesses
            FOR EACH ROW EXECUTE FUNCTION cc_synthetic_unreviewed_readiness();
        SQL
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected ending readiness schema/)
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
  end

  it 'makes destructive rollback explicit instead of removing prospective authority history' do
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to exist
  end
end
