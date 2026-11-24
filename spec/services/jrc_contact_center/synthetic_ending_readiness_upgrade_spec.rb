# Dedicated populated-upgrade harness: regular Rails suites keep rails_helper
# unchanged. Its automatic schema reload would erase this committed baseline.
# Check all pending migrations and the actual receipt without reloading the DB.
owned_environment = ENV['RAILS_ENV'] == 'test' && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
                    ENV['POSTGRES_HOST'] == '127.0.0.1' && ENV['POSTGRES_DATABASE'] == 'jrc_cc_ending_readiness_upgrade_synthetic' &&
                    ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15'
raise 'Exclusive populated-upgrade environment required before application loading' unless owned_environment

require_relative '../../../config/environment'
ActiveRecord::Migration.check_all_pending!
require Rails.root.join('db/migrate/20261123235000_create_contact_center_ending_action_readinesses')
require Rails.root.join('script/jrc_call_center_ending_readiness_schema_probe')
require Rails.root.join('script/jrc_call_center_ending_readiness_upgrade')

RSpec.describe JrcContactCenter::SyntheticEndingReadinessUpgrade do
  before do
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && config.database == 'jrc_cc_ending_readiness_upgrade_synthetic' &&
            ApplicationRecord.connection.current_database == config.database && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15'
    raise 'Exclusive populated M17 readiness-upgrade database required' unless owned
    raise 'Committed upgrade fixtures required' if ApplicationRecord.connection.transaction_open?
    raise 'Readiness migration must be installed before normal RSpec schema checks' unless
      ApplicationRecord.connection.table_exists?(:jrc_contact_center_ending_action_readinesses)
  end

  it 'preserves real native origin, completion, actor and configuration history while installing empty prospective metadata idempotently' do
    before = described_class.verify!
    migration = CreateContactCenterEndingActionReadinesses.new
    migration.up
    expect(described_class.verify!).to eq(before)
    expect(before.fetch(:preserved_records).length).to eq(10)
    expect(before.values_at(:historical_rules_armed, :operational_effects)).to eq([0, 0])
    JrcContactCenter::SyntheticEndingReadinessSchemaProbe.record('populated')
  end
end
