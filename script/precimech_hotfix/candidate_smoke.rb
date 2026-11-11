# Executed on the CI host with RAILS_ENV=test against disposable PG/Redis only.
raise 'Smoke must use its isolated test database' unless Rails.env.test? && ENV['POSTGRES_DATABASE'] == 'precimech_candidate_test'
require 'factory_bot'
require 'webmock'
require 'net/http'
require 'json'
FactoryBot.find_definitions
WebMock.enable!
WebMock.disable_net_connect!(allow_localhost: true)

account = FactoryBot.create(:account)
agent = FactoryBot.create(:user, account: account, role: :agent)
channel = FactoryBot.create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
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
uri = URI("http://127.0.0.1:13000/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{failed.id}/retry")
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
raise 'Image app did not return blocked' unless response&.code == '422' && JSON.parse(response.body).dig('retry', 'status') == 'blocked'
raise 'Image app changed the original attempt' unless failed.reload.attributes == original

normal = FactoryBot.create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                                    content: 'Synthetic image control', additional_attributes: { template_params: template })
SendReplyJob.queue_adapter = :sidekiq
SendReplyJob.perform_later(normal.id)
60.times do
  break if normal.reload.source_id.present?
  sleep 1
end
raise 'Image worker did not correlate the fake provider result' unless normal.reload.source_id == 'wamid.synthetic-image'
redis = Redis.new(url: ENV.fetch('REDIS_URL'))
raise 'Expected exactly one fake provider POST' unless redis.get('precimech_smoke_posts').to_i == 1
callback = { entry: [{ changes: [{ value: { statuses: [{ id: normal.source_id, status: 'delivered' }] } }] }] }.with_indifferent_access
Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: callback).perform
raise 'Callback did not update the matching attempt' unless normal.reload.delivered? && failed.reload.failed?
puts JSON.generate(smoke: 'passed', app_retry: 'blocked', worker_posts: 1, template_language: 'pt_BR', callback: 'delivered')
