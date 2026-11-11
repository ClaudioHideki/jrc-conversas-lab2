# CI host only; no production credentials or external Meta transport.
raise 'Unexpected smoke database' unless Rails.env.test? && ENV['POSTGRES_DATABASE'] == 'precimech_candidate_test'
connection = ActiveRecord::Base.connection_db_config.configuration_hash
raise 'Unexpected connection' unless connection[:database] == 'precimech_candidate_test' &&
                                    connection[:host] == ENV.fetch('SMOKE_DB_HOST') && connection[:port].to_i == 5432
require 'factory_bot'
require 'webmock'
require 'net/http'
require 'json'
WebMock.enable!
WebMock.disable_net_connect!(allow: [ENV.fetch('SMOKE_APP_HOST')])

account = FactoryBot.create(:account)
agent = FactoryBot.create(:user, account: account, role: :agent)
channel = FactoryBot.create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                              provider_config: { api_key: 'test_key', phone_number_id: '123456789',
                                                                 business_account_id: 'synthetic-business' },
                                              sync_templates: false, validate_provider_config: false)
inbox = channel.inbox
FactoryBot.create(:inbox_member, inbox: inbox, user: agent)
conversation = FactoryBot.create(:conversation, inbox: inbox, account: account)
channel.update!(message_templates: [{ name: 'reativacao_cliente_01', language: 'pt_BR', status: 'APPROVED',
                                     category: 'MARKETING', components: [{ type: 'BODY', text: 'Synthetic {{1}}' }] }])
template = { name: 'reativacao_cliente_01', language: 'pt_BR', category: 'MARKETING', processed_params: { body: { '1' => 'Synthetic' } } }
failed = FactoryBot.create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                                    source_id: 'wamid.synthetic-original', status: :failed,
                                    content_attributes: { external_error: '131049: Synthetic restriction' },
                                    additional_attributes: { template_params: template })
original = failed.reload.attributes.deep_dup
headers = agent.create_new_auth_token
uri = URI("http://#{ENV.fetch('SMOKE_APP_HOST')}:3000/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{failed.id}/retry")
response = nil
60.times do
  begin
    request = Net::HTTP::Post.new(uri, headers.merge('Content-Type' => 'application/json'))
    response = Net::HTTP.start(uri.host, uri.port, open_timeout: 2, read_timeout: 5) { |http| http.request(request) }
    break
  rescue Errno::ECONNREFUSED, Net::ReadTimeout, Net::OpenTimeout
    sleep 1
  end
end
raise 'Restricted retry was not blocked' unless response&.code == '422' && JSON.parse(response.body).dig('retry', 'status') == 'blocked'
raise 'Original restriction changed' unless failed.reload.attributes == original

normal = FactoryBot.create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                                    content: 'Synthetic image control', additional_attributes: { template_params: template })
SendReplyJob.queue_adapter = :sidekiq
SendReplyJob.perform_later(normal.id)
SendReplyJob.queue_adapter = :test
60.times do
  break if normal.reload.source_id.present?
  sleep 1
end
raise 'Normal template did not send' unless normal.reload.source_id == 'wamid.synthetic-image'

eligible = FactoryBot.create(:message, account: account, inbox: inbox, conversation: conversation, sender: agent,
                                      message_type: :outgoing, status: :failed, source_id: 'wamid.synthetic-transient-original',
                                      content: 'Synthetic retry', content_attributes: { external_error: '130429: Synthetic limit' },
                                      additional_attributes: { template_params: template }, updated_at: 2.minutes.ago)
eligible_original = eligible.reload.attributes.deep_dup
headers = agent.reload.create_new_auth_token
retry_uri = URI(uri.to_s.sub("/#{failed.id}/retry", "/#{eligible.id}/retry"))
responses = 2.times.map do
  Thread.new do
    request = Net::HTTP::Post.new(retry_uri, headers.merge('Content-Type' => 'application/json'))
    Net::HTTP.start(retry_uri.host, retry_uri.port, open_timeout: 3, read_timeout: 30) { |http| http.request(request) }
  end
end.map(&:value)
raise 'Concurrent retries were not accepted truthfully' unless responses.all? { |item| item.code == '202' }
results = responses.map { |item| JSON.parse(item.body).fetch('retry') }
raise 'Concurrent requests created different attempts' unless results.map { |item| item.fetch('attempt_id') }.uniq.size == 1
raise 'Expected queued and already_requested' unless results.map { |item| item.fetch('status') }.sort == %w[already_requested queued]
attempt = WhatsappRetryAttempt.find(results.first.fetch('attempt_id'))
60.times do
  break if attempt.reload.state == 'read'
  sleep 1
end
raise 'Real worker lost early callback or duplicated correlation' unless attempt.reload.state == 'read' &&
                                                                       attempt.message.source_id == 'wamid.synthetic-retry'
raise 'Eligible original changed' unless eligible.reload.attributes == eligible_original

lost = FactoryBot.create(:message, account: account, inbox: inbox, conversation: conversation, sender: agent,
                                  message_type: :outgoing, status: :failed, source_id: 'wamid.synthetic-lost-original',
                                  content: 'Synthetic recovery', content_attributes: { external_error: '131016: Synthetic unavailable' },
                                  additional_attributes: { template_params: template }, updated_at: 2.minutes.ago)
WhatsappRetryJob.queue_adapter = :test
reserved = Messages::WhatsappRetryService.new(message: lost, actor: agent).perform
recovered = WhatsappRetryAttempt.find(reserved.fetch(:attempt_id))
raise 'Lost enqueue not persisted' unless recovered.state == 'queued'
WhatsappRetryJob.queue_adapter = :sidekiq
WhatsappRetryRecoveryJob.perform_now
60.times do
  break if recovered.reload.state == 'accepted'
  sleep 1
end
raise 'Pending obligation not recovered' unless recovered.reload.state == 'accepted' &&
                                                recovered.message.source_id == 'wamid.synthetic-recovered'
WhatsappRetryJob.perform_later(attempt.id)
redis = Redis.new(url: ENV.fetch('REDIS_URL'))
60.times do
  break if redis.get('precimech_smoke_retry_completed').to_i >= 3
  sleep 1
end
raise 'Expected normal + retry + recovered POSTs only' unless redis.get('precimech_smoke_posts').to_i == 3
raise 'Retry message leaked to legacy SendReplyJob' unless redis.get('precimech_smoke_SendReplyJob').to_i == 1
raise 'Real retry redelivery was not exercised' unless redis.get('precimech_smoke_retry_completed').to_i >= 3
File.write(ENV.fetch('SMOKE_IDS_PATH'), JSON.generate(normal_id: normal.id, original_id: failed.id, inbox_id: inbox.id,
                                                   retry_id: attempt.message_id, recovered_id: recovered.message_id,
                                                   eligible_original_id: eligible.id, lost_original_id: lost.id))
puts JSON.generate(smoke: 'app_and_worker_passed', restricted_retry: 'blocked', concurrent_retry: 'one_attempt_one_post',
                   early_callback: 'read', lost_enqueue: 'recovered', redelivery: 'no_post', worker_posts: 3, template_language: 'pt_BR')
