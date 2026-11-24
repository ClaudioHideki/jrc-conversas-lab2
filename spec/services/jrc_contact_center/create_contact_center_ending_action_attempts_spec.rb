require 'rails_helper'
require Rails.root.join('db/migrate/20261124001000_create_contact_center_ending_action_attempts')

# Private native preparation. These examples run only after explicit source
# admission and installation in the workflow-owned disposable databases.
RSpec.describe CreateContactCenterEndingActionAttempts do
  subject(:migration) { described_class.new }

  include_context 'with native ending execution original evidence'

  it 'installs or verifies empty history without queuing work, creating effects or enabling a rule' do
    versions = JrcContactCenter::EndingActionVersion.where(account: account).pluck(:id)
    settings = account.reload.settings.deep_dup
    expect { migration.up }.not_to raise_error
    expect(JrcContactCenter::EndingActionAttempt.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingActionAttemptOutcome.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
    actual = [JrcContactCenter::EndingActionVersion.where(account: account).pluck(:id), account.reload.settings]
    expect(actual).to eq([versions, settings])
  end

  it 'rejects removal of an immutable attempt trigger instead of repairing unknown history' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute('DROP TRIGGER cc_ending_attempt_immutable ON jrc_contact_center_ending_action_attempts')
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected ending attempt history/)
  end

  it 'rejects removal of the exact current-account original reference' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.remove_foreign_key(:jrc_contact_center_ending_action_attempts, name: 'cc_ending_attempt_origin_fk')
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected ending attempt history/)
  end

  it 'rejects removal of the composite reference to an atomic success receipt' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.remove_foreign_key(:jrc_contact_center_ending_action_attempt_outcomes, name: 'cc_ending_outcome_execution_fk')
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected ending attempt history/)
  end

  it 'does not accept an altered receipt comment or silently stamp the mismatch' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.change_table_comment(:jrc_contact_center_ending_action_attempts, 'SYNTHETIC unknown state')
        migration.up
      end
    end.to raise_error(ActiveRecord::MigrationError, /Unexpected ending attempt history/)
  end

  it 'refuses to remove durable attempts and terminal history through an ordinary rollback' do
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    expect(JrcContactCenter::EndingActionAttempt.where(account: account)).to be_empty
  end
end
