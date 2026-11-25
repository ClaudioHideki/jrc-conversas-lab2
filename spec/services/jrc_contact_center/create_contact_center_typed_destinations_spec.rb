require 'rails_helper'
require Rails.root.join('db/migrate/20261125060000_create_contact_center_typed_destinations')

# Prepared migration integrity cases. These run only after owned synthetic
# installation and again after schema reload; no real environment is targeted.
RSpec.describe CreateContactCenterTypedDestinations do
  subject(:migration) { described_class.new }

  include_context 'with native ending execution original evidence'

  it 'reverifies an exact installation without creating work, granting access or altering the native catalogue' do
    settings = account.reload.settings.deep_dup
    versions = JrcContactCenter::EndingActionVersion.where(account: account).pluck(:id)
    members = account.account_users.order(:id).map(&:attributes)
    expect { migration.up }.not_to raise_error
    described_class::TABLES.each do |table|
      query = "SELECT count(*) FROM #{table} WHERE account_id = #{Integer(account.id)}"
      expect(ApplicationRecord.connection.select_value(query).to_i).to eq(0)
    end
    expect(account.reload.settings).to eq(settings)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).pluck(:id)).to eq(versions)
    expect(account.account_users.order(:id).map(&:attributes)).to eq(members)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'refuses a missing immutable attempt trigger rather than repairing unknown history' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute('DROP TRIGGER cc_typed_attempt_immutable ON jrc_contact_center_ending_destination_attempts')
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unknown typed ending history references or functions/)
  end

  it 'refuses a disabled outcome trigger even when its name is unchanged' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute('ALTER TABLE jrc_contact_center_ending_destination_outcomes DISABLE TRIGGER cc_typed_outcome_immutable')
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected typed ending history/)
  end

  it 'refuses removal of the composite attempt-to-original scope reference' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.remove_foreign_key(:jrc_contact_center_ending_destination_attempts, name: 'cc_typed_attempt_origin_fk')
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unknown typed ending history references or functions/)
  end

  it 'refuses removal of the composite outcome-to-success scope reference' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.remove_foreign_key(:jrc_contact_center_ending_destination_outcomes, name: 'cc_typed_outcome_execution_fk')
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unknown typed ending history references or functions/)
  end

  it 'refuses a malformed partial installation without dropping or rebuilding the remaining tables' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute('DROP TABLE jrc_contact_center_ending_destination_consents CASCADE')
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Incomplete typed ending history/)
    expect(ApplicationRecord.connection.table_exists?(:jrc_contact_center_ending_destination_consents)).to be true
  end

  it 'refuses a changed table comment instead of silently restamping it' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.change_table_comment(:jrc_contact_center_ending_destination_attempts, 'SYNTHETIC unknown typed history')
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected typed ending history/)
  end

  it 'refuses removal of the one-native-success index' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.remove_index(:jrc_contact_center_ending_destination_executions, name: 'cc_typed_one_native_success')
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected typed ending history/)
  end

  it 'refuses to turn a deferred composite reference into an immediate reference' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute(<<~SQL)
          ALTER TABLE jrc_contact_center_ending_destination_attempts
          ALTER CONSTRAINT cc_typed_attempt_origin_fk NOT DEFERRABLE;
        SQL
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unknown typed ending history references or functions/)
  end

  it 'refuses altered source-to-result checks without weakening or replacing them' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.remove_check_constraint(:jrc_contact_center_ending_destination_outcomes, name: 'cc_typed_outcome_result')
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected typed ending history/)
  end

  it 'keeps the new immutable history irreversible through an ordinary rollback' do
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    expect(ApplicationRecord.connection.table_exists?(:jrc_contact_center_ending_destination_attempts)).to be true
  end
end
