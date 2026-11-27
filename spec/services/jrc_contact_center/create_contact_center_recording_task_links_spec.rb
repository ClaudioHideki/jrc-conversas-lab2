# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261127003000_create_contact_center_recording_task_links')

RSpec.describe CreateContactCenterRecordingTaskLinks do
  let(:migration) { described_class.new }
  let(:connection) { ApplicationRecord.connection }
  let(:table) { described_class::TABLE }

  it 'verifies the current installation without changing an account or automatically granting destination capabilities' do
    account = create(:account)
    original = account.reload.attributes
    members = account.account_users.order(:id).map(&:attributes)
    expect { migration.up }.not_to raise_error
    expect(account.reload.attributes).to eq(original)
    expect(account.account_users.order(:id).map(&:attributes)).to eq(members)
    expect(JrcContactCenter::RecordingTaskLink.where(account: account)).to be_empty
  end

  it 'refuses missing or disabled append/immutability guards rather than repairing unknown history' do
    statements = [
      "DROP TRIGGER cc_recording_task_append_guard ON #{table}",
      "ALTER TABLE #{table} DISABLE TRIGGER cc_recording_task_immutable_guard"
    ]
    statements.each do |statement|
      expect do
        ApplicationRecord.transaction(requires_new: true) do
          connection.execute(statement)
          migration.up
        end
      end.to raise_error(ActiveRecord::MigrationError, /Unknown recording task/)
    end
  end

  it 'rejects a changed account FK, unique request index, scope CHECK or schema receipt without changing native data' do
    changes = [
      -> { connection.remove_foreign_key(table, name: 'cc_recording_task_account_fk') },
      -> { connection.remove_index(table, name: 'cc_recording_task_request') },
      -> { connection.remove_check_constraint(table, name: 'cc_recording_task_scope') },
      -> { connection.change_table_comment(table, 'SYNTHETIC unverified source') }
    ]
    changes.each do |change|
      expect do
        ApplicationRecord.transaction(requires_new: true) do
          change.call
          migration.up
        end
      end.to raise_error(ActiveRecord::MigrationError, /Unknown recording task/)
    end
  end

  it 'preserves recording-task history instead of implementing a destructive normal rollback' do
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    expect(connection.table_exists?(table)).to be(true)
  end
end
