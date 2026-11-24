# Native boot preserves the committed pre-migration baseline. Never replace it
# with fixtures or disable the normal pending-migration check.
owned_environment = ENV['RAILS_ENV'] == 'test' && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
                    ENV['POSTGRES_HOST'] == '127.0.0.1' && ENV['POSTGRES_DATABASE'] == 'jrc_cc_ending_attempt_upgrade_synthetic' &&
                    ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15'
raise 'Exclusive attempt-upgrade environment required before application loading' unless owned_environment

require_relative '../../../config/environment'
ActiveRecord::Migration.check_all_pending!
require Rails.root.join('db/migrate/20261124001000_create_contact_center_ending_action_attempts')
require Rails.root.join('script/jrc_call_center_ending_attempt_upgrade')
require Rails.root.join('script/jrc_call_center_ending_attempt_schema_probe')

RSpec.describe JrcContactCenter::SyntheticEndingAttemptUpgrade do
  it 'preserves the real M19 automated success, its Task and audit and the earlier manual Task without queuing old work' do
    before = described_class.verify!
    CreateContactCenterEndingActionAttempts.new.up
    expect(described_class.verify!).to eq(before)
    expect(before.fetch(:preserved_records).length).to eq(17)
    expect(before.values_at(:existing_tasks_preserved, :successful_receipts_preserved)).to eq([2, 1])
    expect(before.values_at(:queued_attempts, :terminal_outcomes, :operational_effects_delta)).to eq([0, 0, 0])
    JrcContactCenter::SyntheticEndingAttemptSchemaProbe.record('populated')
  end
end
