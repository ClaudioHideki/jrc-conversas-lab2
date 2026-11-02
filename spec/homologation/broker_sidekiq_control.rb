require 'json'
abort 'LAB_ONLY' unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database == 'jrc_durable_review_test'
queue = 'broker_homologation_20261102'
JrcBroker::WebhookObligationJob.queue_name = queue
case ARGV.first
when 'seed'
  require 'factory_bot_rails'
  FactoryBot.find_definitions if FactoryBot.factories.count.zero?
  ActiveRecord::Base.connection.execute('CREATE TABLE IF NOT EXISTS jrc_lab_sidekiq_receipts (delivery_id uuid PRIMARY KEY, account_id bigint NOT NULL, body_hash text NOT NULL)')
  ids = 2.times.map do
    account = FactoryBot.create(:account)
    inbox = FactoryBot.create(:channel_api, account: account).inbox
    JrcBrokerIntegration.create!(account: account, broker_origin: 'https://broker.example.test', organization_id: SecureRandom.uuid,
                                 destination_revision: 1, encrypted_control_key: 'synthetic-not-used')
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid)
    message = FactoryBot.create(:message, account: account, inbox: inbox, message_type: :outgoing)
    JrcBrokerWebhookObligation.find_by!(message_id: message.id).id
  end
  File.write('/tmp/sidekiq-fixture.json', { ids: ids }.to_json)
  ActiveJob::Base.queue_adapter = :sidekiq
  ids.each { |id| JrcBroker::WebhookObligationJob.perform_later(id) }
  puts({ seeded: ids.size, queue: queue }.to_json)
when 'recover'
  ids = JSON.parse(File.read('/tmp/sidekiq-fixture.json')).fetch('ids')
  rows = JrcBrokerWebhookObligation.where(id: ids)
  raise 'NOT_RUNNING_AFTER_CRASH' unless rows.where(state: 'running').count == 1
  # Controlled expiry replaces a five-minute wait; no claim about wall-clock TTL is made.
  rows.where(state: 'running').update_all(lease_until: 1.second.ago)
  ActiveJob::Base.queue_adapter = :sidekiq
  JrcBroker::WebhookRecoveryJob.perform_now
  rows.each { |row| JrcBroker::WebhookObligationJob.perform_later(row.id) }
  puts({ recovered: true, duplicatesEnqueued: true }.to_json)
when 'verify'
  ids = JSON.parse(File.read('/tmp/sidekiq-fixture.json')).fetch('ids')
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 45
  loop do
    break if JrcBrokerWebhookObligation.uncached { JrcBrokerWebhookObligation.where(id: ids, state: 'delivered').count } == 2
    raise 'DELIVERY_TIMEOUT' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    sleep 0.25
  end
  rows = JrcBrokerWebhookObligation.where(id: ids).order(:id).to_a
  connection = ActiveRecord::Base.connection
  receipts = connection.exec_query("SELECT delivery_id,account_id FROM jrc_lab_sidekiq_receipts WHERE delivery_id IN (#{rows.map { |r| connection.quote(r.delivery_id) }.join(',')})").to_a
  raise 'DUPLICATE_OR_TENANT_CONFLICT' unless receipts.size == 2 && rows.all? { |r| receipts.any? { |x| x['delivery_id'] == r.delivery_id && x['account_id'] == r.account_id } }
  puts({ realSidekiq: Sidekiq::VERSION, realRedis: true, realRails: Rails.version, persistedReceipts: receipts.size,
         accounts: rows.map(&:account_id).uniq.size, states: rows.map(&:state), attempts: rows.map(&:attempts),
         producerCrashAfterReceiverCommit: true, transport: 'synthetic port / PostgreSQL receipt', independentChatwootInstallations: false }.to_json)
else
  abort 'UNKNOWN_PHASE'
end
