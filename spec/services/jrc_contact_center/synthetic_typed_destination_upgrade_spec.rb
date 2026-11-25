require 'rails_helper'
require Rails.root.join('script/jrc_call_center_typed_destination_upgrade')

# Prepared exclusive populated-upgrade verification. Never run against the
# ordinary test database, a developer service or a real account.
RSpec.describe JrcContactCenter::SyntheticTypedDestinationUpgrade do
  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' && config.configuration_hash[:host] == '127.0.0.1' &&
            ApplicationRecord.connection.current_database == described_class::DATABASE
    raise 'Exclusive typed ending populated upgrade verification required' unless owned

    example.run
  end

  def upgrade_report
    JSON.parse(File.read(described_class::AFTER))
  end

  it 'preserves exact old columns and values through installation and an idempotent second application' do
    report = upgrade_report
    expect(report).to include('sha' => ENV.fetch('GITHUB_SHA'), 'synthetic' => true,
                             'exact_old_columns_and_values_preserved' => true, 'rerun_idempotent' => true)
    expect(report.fetch('preserved_records').length).to be >= 19
    expect(report.fetch('preserved_records').all? { |row| row.fetch('sha256').match?(/\A[0-9a-f]{64}\z/) }).to be true
  end

  it 'preserves the manual and automated Tasks, v1 success and its completed durable attempt' do
    expect(upgrade_report).to include('existing_tasks_preserved' => 2, 'successful_v1_receipts_preserved' => 1,
                                     'completed_v1_attempts_preserved' => 1, 'completed_v1_outcomes_preserved' => 1)
    expect(JrcProjects::Task.count).to eq(2)
    expect(JrcContactCenter::EndingActionExecution.count).to eq(1)
    expect(JrcContactCenter::EndingActionAttemptOutcome.sole.outcome).to eq('succeeded')
  end

  it 'creates no new typed rows, operational effect or automatic execution of former calls' do
    expect(upgrade_report).to include('typed_rows' => 0, 'operational_effects_delta' => 0)
    described_class::TABLES.each do |table|
      expect(ApplicationRecord.connection.select_value("SELECT count(*) FROM #{table}").to_i).to eq(0)
    end
  end
end
