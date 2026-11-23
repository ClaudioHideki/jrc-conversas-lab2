require 'rails_helper'
require Rails.root.join('db/migrate/20261123180000_create_contact_center_ending_execution_origins')

# Prepared, not run. Deliberate tampering is confined to rollbackable test DDL;
# it verifies that rerunning the migration refuses to repair an unproven schema.
RSpec.describe CreateContactCenterEndingExecutionOrigins do
  subject(:migration) { described_class.new }

  include_context 'with native ending execution original evidence'

  it 'verifies an identical installed schema without changing original attendance, configuration or version history' do
    first = origin.attributes.deep_dup
    settings = account.reload.settings.deep_dup
    versions = JrcContactCenter::EndingActionVersion.where(account: account).pluck(:id)
    expect { migration.up }.not_to raise_error
    expect(origin.reload.attributes).to eq(first)
    expect(account.reload.settings).to eq(settings)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).pluck(:id)).to eq(versions)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'refuses a missing owned completion table instead of silently rebuilding it or rewriting source records' do
    connection = ApplicationRecord.connection
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        connection.drop_table(:jrc_contact_center_ending_action_completions)
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected ending execution origin schema/)
    expect(connection.table_exists?(:jrc_contact_center_ending_action_completions)).to be(true)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'refuses missing owned leg evidence without changing the native call or reason catalogue' do
    connection = ApplicationRecord.connection
    first = account.reload.settings.deep_dup
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        connection.remove_column(:jrc_contact_center_call_legs, :ending_action_captured_started_at)
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected ending execution origin schema/)
    expect(account.reload.settings).to eq(first)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'detects a missing immutable-origin trigger' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute('DROP TRIGGER cc_ending_action_origin_immutable ON jrc_contact_center_ending_action_origins')
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected ending execution origin schema/)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'detects removal of the exact composite source-scope foreign key and its account boundary' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.remove_foreign_key(:jrc_contact_center_ending_action_origins, name: 'cc_ending_execution_origin_scope_fk')
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected ending execution origin schema/)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'refuses an altered schema receipt instead of stamping over unknown infrastructure' do
    connection = ApplicationRecord.connection
    first = connection.table_comment(:jrc_contact_center_ending_action_origins)
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        connection.change_table_comment(:jrc_contact_center_ending_action_origins, 'SYNTHETIC_UNPROVEN_RECEIPT')
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected ending execution origin schema/)
    expect(connection.table_comment(:jrc_contact_center_ending_action_origins)).to eq(first)
  end

  it 'uses the existing immutable technical account reference and adds no live actor foreign key' do
    keys = ApplicationRecord.connection.foreign_keys(:jrc_contact_center_ending_action_origins)
    expect(keys.map(&:to_table).sort).to eq(%w[jrc_contact_center_ending_action_queue_scopes jrc_contact_center_ending_action_versions
                                               jrc_contact_center_ending_scope_accounts jrc_contact_center_qualifications])
    expect(keys.find { |key| key.to_table == 'jrc_contact_center_qualifications' }.on_delete).to eq(:nullify)
    expect(JrcContactCenter::EndingActionOrigin.column_names).not_to include('updated_at')
    expect(JrcContactCenter::EndingActionCompletion.column_names).not_to include('updated_at')
  end

  it 'makes rollback explicit instead of erasing immutable original and completion evidence' do
    original = origin.attributes.deep_dup
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    expect(origin.reload.attributes).to eq(original)
    expect(JrcContactCenter::Qualification.exists?(qualification.id)).to be(true)
  end
end
