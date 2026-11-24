# PRIVATE CANDIDATE. Actual application boot without purging the committed baseline.
owned_environment = ENV['RAILS_ENV'] == 'test' && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
                    ENV['POSTGRES_HOST'] == '127.0.0.1' && ENV['POSTGRES_DATABASE'] == 'jrc_cc_ending_success_upgrade_synthetic' &&
                    ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15'
raise 'Exclusive success-upgrade environment required before application loading' unless owned_environment

require_relative '../../../config/environment'
ActiveRecord::Migration.check_all_pending!
require Rails.root.join('db/migrate/20261124000000_create_contact_center_ending_action_executions')
require Rails.root.join('script/jrc_call_center_ending_execution_schema_probe')
require Rails.root.join('script/jrc_call_center_ending_success_upgrade')

RSpec.describe JrcContactCenter::SyntheticEndingExecutionUpgrade do
  before do
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && config.database == 'jrc_cc_ending_success_upgrade_synthetic' &&
            ApplicationRecord.connection.current_database == config.database && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15'
    raise 'Exclusive populated M18 success-upgrade database required' unless owned
    raise 'Committed upgrade fixtures required' if ApplicationRecord.connection.transaction_open?
    raise 'Success ledger migration must be installed before native schema checks' unless
      ApplicationRecord.connection.table_exists?(:jrc_contact_center_ending_action_executions)
  end

  it 'preserves the real M18 activation, call, completion, manual task and audit without inventing success or retroactive effects' do
    before = described_class.verify!
    CreateContactCenterEndingActionExecutions.new.up
    expect(described_class.verify!).to eq(before)
    expect(before.fetch(:preserved_records).length).to eq(14)
    expect(before.values_at(:existing_tasks_preserved, :readiness_records_preserved)).to eq([1, 1])
    expect(before.values_at(:successful_receipts, :operational_effects_delta)).to eq([0, 0])
    JrcContactCenter::SyntheticEndingExecutionSchemaProbe.record('populated')
  end
end
