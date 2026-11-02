# Explicit Rails-runner phases. Run only in the two freshly created fixture DBs.
require_relative 'broker_https_harness'
require 'net/http'
require 'securerandom'

runtime = BrokerHttpsHarness.runtime!(ENV)
abort 'RAILS_TEST_DATABASE_MISMATCH' unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database == runtime.fetch('database')
ActiveJob::Base.queue_adapter = :sidekiq
JrcBroker::WebhookObligationJob.queue_name = runtime.fetch('queue')
JrcBroker::WebhookRecoveryJob.queue_name = runtime.fetch('queue')
directory = runtime.fetch('directory')
key = runtime.fetch('key')
participant_path = File.join(directory, "participant_#{key}.json")
manifest_path = File.join(directory, 'manifest.json')

def fixture_row!(context)
  row = JrcBrokerWebhookObligation.uncached { JrcBrokerWebhookObligation.find(context.fetch('obligation_id')) }
  expected = context.slice('account_id', 'inbox_id', 'message_id', 'delivery_id', 'integration_id', 'instance_id')
  raise 'OBLIGATION_SCOPE_CHANGED' unless expected.all? { |name, value| row.public_send(name) == value }
  raise 'BINDING_CHANGED' unless row.current_binding?

  row
end

def fixture_evidence!(manifest, key)
  uri = URI("#{BrokerHttpsHarness::ORIGIN}/_lab/evidence/#{key}")
  request = Net::HTTP::Get.new(uri)
  request['X-Lab-Control'] = manifest.fetch('control_token')
  response = Net::HTTP.start(
    uri.host, uri.port,
    use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_PEER,
    ca_file: ENV.fetch('SSL_CERT_FILE'), open_timeout: 5, read_timeout: 5
  ) { |http| http.request(request) }
  raise 'LAB_EVIDENCE_REJECTED' unless response.is_a?(Net::HTTPSuccess)

  JSON.parse(response.body)
end

case ARGV.fetch(0)
when 'prepare'
  raise 'FIXTURE_ALREADY_PREPARED' if File.exist?(participant_path) || Account.exists?

  require 'factory_bot_rails'
  FactoryBot.find_definitions if FactoryBot.factories.count.zero?
  account = FactoryBot.create(:account)
  account.enable_features!('jrc_broker')
  channel = FactoryBot.create(:channel_api, account: account)
  sender = FactoryBot.create(:user, account: account, role: :administrator)
  participant = { 'key' => key, 'database' => runtime.fetch('database'), 'account_id' => account.id,
                  'inbox_id' => channel.inbox.id, 'sender_id' => sender.id, 'webhook_secret' => channel.secret,
                  'chatwoot_origin' => "https://lab2-#{key}.example.test" }
  raise 'MISSING_REAL_API_INBOX_SECRET' if channel.secret.blank?

  BrokerHttpsHarness.write_json!(directory, "participant_#{key}.json", participant)
  puts JSON.generate(prepared: true, key: key, account_id: account.id, inbox_id: channel.inbox.id)
when 'commit'
  require 'factory_bot_rails'
  FactoryBot.find_definitions if FactoryBot.factories.count.zero?
  manifest = JSON.parse(File.read(manifest_path))
  context = manifest.fetch('contexts').find { |item| item.fetch('key') == key }
  raise 'MANIFEST_DATABASE_MISMATCH' unless context.fetch('database') == runtime.fetch('database')

  account = Account.find(context.fetch('account_id'))
  inbox = account.inboxes.find(context.fetch('inbox_id'))
  raise 'FIXTURE_ALREADY_COMMITTED' if JrcBrokerWebhookObligation.exists?

  ciphertext = JrcBroker::Configuration.credential_store.encrypt(account_id: account.id, token: manifest.fetch('control_token'))
  JrcBrokerIntegration.create!(account: account, broker_origin: BrokerHttpsHarness::ORIGIN,
                               organization_id: context.fetch('organization_id'), destination_revision: 1, encrypted_control_key: ciphertext)
  inbox.channel.update!(webhook_url: "#{BrokerHttpsHarness::ORIGIN}/v1/integrations/chatwoot/#{context.fetch('integration_id')}/events")
  JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: context.fetch('integration_id'),
                                instance_id: context.fetch('instance_id'))
  conversation = FactoryBot.create(:conversation, account: account, inbox: inbox).reload
  raise 'CONVERSATION_DISPLAY_ID_NOT_COMMITTED' unless conversation.display_id.is_a?(Integer) && conversation.display_id.positive?

  message = Message.transaction do
    FactoryBot.create(:message, account: account, inbox: inbox, conversation: conversation, sender: User.find(context.fetch('sender_id')),
                                message_type: :outgoing, private: false, content: 'Synthetic Broker HTTPS custody probe')
  end
  raise 'MESSAGE_TRANSACTION_STILL_OPEN' if ActiveRecord::Base.connection.transaction_open?

  row = JrcBrokerWebhookObligation.find_by!(message_id: message.id).reload
  payload = row.payload.deep_symbolize_keys
  participant = context.merge('message_id' => message.id, 'conversation_id' => row.payload.fetch('conversation').fetch('id'),
                              'obligation_id' => row.id, 'delivery_id' => row.delivery_id,
                              'body_sha256' => Digest::SHA256.hexdigest(payload.to_json), 'destination_revision' => 1)
  BrokerHttpsHarness.write_json!(directory, "participant_#{key}.json", participant)
  puts JSON.generate(committed: true, key: key, obligation_id: row.id, message_id: message.id, queue: runtime.fetch('queue'))
when 'recover', 'recover-crash'
  manifest = JSON.parse(File.read(manifest_path))
  context = manifest.fetch('contexts').find { |item| item.fetch('key') == key }
  row = fixture_row!(context)
  if ARGV.first == 'recover-crash'
    crash = JSON.parse(File.read(File.join(directory, "worker_#{key}_killed.json")))
    raise 'NO_CONFIRMED_CRASH_LEASE' unless row.state == 'running' && crash.fetch('delivery_id') == row.delivery_id

    # Controlled fixture expiry, not a claim that the real five-minute TTL elapsed.
    row.update!(lease_until: 1.second.ago)
  else
    raise 'NOT_RETRYABLE_PENDING' unless row.state == 'pending'

    sleep 0.1 while row.reload.available_at > Time.current
  end
  JrcBroker::WebhookRecoveryJob.perform_now
  JrcBroker::WebhookObligationJob.perform_later(row.id)
  puts JSON.generate(recovery_enqueued: true, duplicate_enqueued: true, key: key, delivery_id: row.delivery_id)
when 'foreign-signature'
  raise 'SOURCE_A_REQUIRED' unless key == 'a'

  manifest = JSON.parse(File.read(manifest_path))
  source = manifest.fetch('contexts').find { |item| item.fetch('key') == 'a' }
  target = manifest.fetch('contexts').find { |item| item.fetch('key') == 'b' }
  row = fixture_row!(source)
  before = fixture_evidence!(manifest, 'b').fetch('counts')
  body = row.payload.deep_symbolize_keys.to_json
  timestamp = Time.now.to_i.to_s
  signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', row.message.inbox.channel.secret, "#{timestamp}.#{body}")}"
  begin
    SafeFetch.fetch(
      "#{runtime.fetch('origin')}/v1/integrations/chatwoot/#{target.fetch('integration_id')}/events",
      method: :post,
      body: body, validate_content_type: false, max_bytes: 4096,
      headers: { 'Content-Type' => 'application/json', 'X-Chatwoot-Timestamp' => timestamp,
                 'X-Chatwoot-Signature' => signature, 'X-Chatwoot-Delivery' => row.delivery_id,
                 'X-Lab-Negative-Probe' => manifest.fetch('run_id'), 'X-Lab-Control' => manifest.fetch('control_token') }
    ) { |_result| nil }
    raise 'FOREIGN_SIGNATURE_WAS_ACCEPTED'
  rescue SafeFetch::HttpError => e
    raise unless e.message.start_with?('401 ')
  end
  raise 'FOREIGN_SIGNATURE_CHANGED_TARGET' unless fixture_evidence!(manifest, 'b').fetch('counts') == before

  BrokerHttpsHarness.write_json!(directory, 'foreign_signature.json', { 'rejected' => true, 'http_status' => 401, 'target_unchanged' => true })
  puts JSON.generate(foreign_signature_rejected: true, http_status: 401, target_unchanged: true)
when 'verify'
  manifest = JSON.parse(File.read(manifest_path))
  BrokerHttpsHarness.contexts!(manifest.fetch('contexts'))
  context = manifest.fetch('contexts').find { |item| item.fetch('key') == key }
  row = fixture_row!(context)
  evidence = fixture_evidence!(manifest, key)
  obligation = row.attributes.slice('state', 'delivery_id', 'account_id', 'inbox_id', 'message_id', 'attempts')
  BrokerHttpsHarness.verify!(context, broker_counts: evidence.fetch('counts'), wire_requests: evidence.fetch('wire_requests'), obligation: obligation)
  raise 'UNEXPECTED_REAL_ATTEMPT_COUNT' unless row.attempts == (key == 'a' ? 3 : 2)
  raise 'OUTAGE_AFTER_COMMIT_NOT_OBSERVED' unless evidence.fetch('wire_requests').any? { |request| request['upstream_unavailable'] == true }

  if key == 'a'
    raise 'REAL_KILL_PROOF_MISSING' unless File.exist?(File.join(directory, 'worker_a_killed.json'))
    raise 'ACK_LOSS_AFTER_COMMIT_NOT_OBSERVED' unless evidence.fetch('wire_requests').any? do |request|
      request['ack_withheld_after_commit'] == true && request['client_disconnected_before_ack'] == true
    end
  end
  result = { gate: 'LAB2_TLS_BROKER_DURABLE_CUSTODY', key: key, independent_lab2_consumers: 2,
             stock_chatwoot_cclx_homologated: false, physical_whatsapp_delivery: 'NOT_EXERCISED',
             obligation: obligation, broker: evidence.fetch('counts'), wire_requests: evidence.fetch('wire_requests') }
  BrokerHttpsHarness.write_json!(directory, "proof_#{key}.json", result)
  puts JSON.generate(result)
else
  abort 'UNKNOWN_HTTPS_LAB_PHASE'
end
