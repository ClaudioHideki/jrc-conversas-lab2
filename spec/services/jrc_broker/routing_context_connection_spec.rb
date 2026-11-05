require 'rails_helper'
require 'database_cleaner/active_record'

# Committed fixtures are required: the release helper deliberately preserves open transactions.
RSpec.describe JrcBroker::RoutingContext do
  self.use_transactional_tests = false
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:origin) { 'https://broker.example.test' }
  let(:organization_id) { SecureRandom.uuid }
  let(:integration_id) { SecureRandom.uuid }
  let(:prefix) { "#{origin}/v1/integrations/chatwoot/control" }

  around do |example|
    database = ActiveRecord::Base.connection_db_config.database
    disposable = Rails.env.test? && ENV['JRC_SD_CONCURRENCY'] == '1' &&
                 %w[jrc_sd_bc_portal_concurrency_20261025_test jrc_durable_review_test].include?(ENV['POSTGRES_DATABASE']) &&
                 database == ENV['POSTGRES_DATABASE'] && ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'
    raise 'Explicitly named disposable PostgreSQL CI database required' unless disposable

    DatabaseCleaner.clean_with(:deletion)
    with_modified_env(JRC_BROKER_ENABLED: 'true', JRC_BROKER_ALLOWED_ORIGINS: origin,
                      JRC_BROKER_CREDENTIAL_KEY: Base64.strict_encode64('r' * 32),
                      FRONTEND_URL: 'https://central.example.test') { example.run }
  ensure
    clear_enqueued_jobs if disposable
    DatabaseCleaner.clean_with(:deletion) if disposable
  end

  it 'releases the idle pool connection during both real Context and routing HTTP reads, then revalidates locally' do
    account.enable_features!('jrc_broker')
    agent
    ciphertext = JrcBroker::Configuration.credential_store.encrypt(account_id: account.id, token: 'synthetic-routing-key')
    integration = JrcBrokerIntegration.create!(account: account, broker_origin: origin, organization_id: organization_id,
                                               destination_revision: 1, encrypted_control_key: ciphertext)
    binding = JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: integration_id, instance_id: SecureRandom.uuid)
    create(:inbox_member, inbox: inbox, user: agent)
    # Materialize all fixture attributes and JSON before the HTTP callbacks: no lazy let/query can lease the pool there.
    context_body = { organizationId: integration.organization_id, accountId: account.id, destinationRevision: 1,
                     chatwootOrigin: 'https://central.example.test' }.to_json
    routing_body = { schemaVersion: 1, organizationId: integration.organization_id, accountId: account.id,
                     destinationRevision: 1, checkedAt: Time.current.iso8601,
                     data: [{ integrationId: binding.integration_id, channelId: SecureRandom.uuid, inboxId: inbox.id,
                              state: 'NONE', ownerRevision: nil, bindingRevision: nil }] }.to_json
    expected = { inbox.id => 'NONE' }
    targets = [binding]
    pool = ActiveRecord::Base.connection_pool
    observations = []
    paths = [["#{prefix}/context", context_body], ["#{prefix}/routing-context?integrationIds=#{binding.integration_id}", routing_body]]
    paths.each do |url, body|
      stub_request(:get, url).to_return do
        connection = pool.active_connection?
        observations << [connection.present?, connection&.transaction_open? == true]
        { status: 200, headers: { 'Content-Type' => 'application/json' }, body: body }
      end
    end
    expect(pool.active_connection?).to be_present
    expect(pool.active_connection?.transaction_open?).to be(false)

    result = described_class.new(account: account, user: agent, bindings: targets).perform

    expect(observations).to eq([[false, false], [false, false]])
    expect(result).to eq(expected)
    expect(pool.active_connection?).to be_present # The preserved reload/uncached tuple checks acquire it after HTTP.
    paths.each { |url, _| expect(WebMock).to have_requested(:get, url).once }
    expect(WebMock).not_to have_requested(:post, /broker\.example\.test/)
  end
end
