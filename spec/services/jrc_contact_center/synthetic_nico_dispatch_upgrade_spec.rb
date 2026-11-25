# Native committed baseline is prepared by a separate Rails runner before the
# migration. Do not replace it with transactional fixtures or bypass pending gates.
owned_environment = ENV['RAILS_ENV'] == 'test' && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
                    ENV['POSTGRES_HOST'] == '127.0.0.1' && ENV['POSTGRES_DATABASE'] == 'jrc_cc_nico_intent_upgrade_synthetic' &&
                    ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15'
raise 'Exclusive native NICO upgrade environment required before application loading' unless owned_environment

require_relative '../../../config/environment'
ActiveRecord::Migration.check_all_pending!
require Rails.root.join('script/jrc_call_center_native_nico_dispatch_upgrade')

RSpec.describe JrcContactCenter::SyntheticNicoDispatchUpgrade do
  it 'preserves the full committed M20 and existing Helpdesk baseline without requesting historical NICO delivery' do
    first = described_class.verify!
    expect(described_class.verify!).to eq(first)
    expect(first.fetch(:preserved_records).length).to eq(27)
    expect(first.values_at(:existing_tasks, :existing_native_successes, :existing_tickets, :legacy_events)).to eq([2, 1, 1, 1])
    expect(first.fetch(:technical_intents)).to eq(0)
    expect(first.fetch(:exact_old_columns_and_values_preserved)).to be(true)
    expect(first.fetch(:provider_or_broker_execution)).to be(false)
  end
end
