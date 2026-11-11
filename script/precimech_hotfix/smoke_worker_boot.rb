require '/app/config/environment'
require 'json'

# Test transport only, mounted read-only at runtime; never copied into the image.
module PrecimechSmokeTransport
  def get(url, options = {})
    raise 'Unexpected smoke GET' unless url == 'https://graph.facebook.com/v14.0/synthetic-business/message_templates'
    raise 'Unexpected template query' unless options.dig(:query, :name) == 'reativacao_cliente_01'
    response = Struct.new(:parsed_response).new({
      'data' => [{ 'name' => 'reativacao_cliente_01', 'language' => 'pt_BR', 'status' => 'APPROVED',
                   'category' => 'MARKETING', 'components' => [{ 'type' => 'BODY', 'text' => 'Synthetic {{1}}' }] }]
    })
    response.define_singleton_method(:success?) { true }
    response.define_singleton_method(:code) { 200 }
    response
  end

  def post(url, options = {})
    raise 'Unexpected smoke transport URL' unless url == 'https://graph.facebook.com/v13.0/123456789/messages'

    body = JSON.parse(options.fetch(:body))
    raise 'Expected pt_BR template' unless body['type'] == 'template' && body.dig('template', 'language', 'code') == 'pt_BR'
    raise 'Unexpected template name' unless body.dig('template', 'name') == 'reativacao_cliente_01'
    raise 'Unexpected parameters' unless body.dig('template', 'components', 0, 'parameters', 0, 'text') == 'Synthetic'

    index = Redis.new(url: ENV.fetch('REDIS_URL')).incr('precimech_smoke_posts')
    raise 'Unexpected duplicate POST' unless (1..3).cover?(index)
    id = ['wamid.synthetic-image', 'wamid.synthetic-retry', 'wamid.synthetic-recovered'][index - 1]
    if index == 2
      attempt = WhatsappRetryAttempt.find_by!(state: 'submitting')
      callback = { entry: [{ changes: [{ value: { statuses: [{ id: id, status: 'read' }] } }] }] }.with_indifferent_access
      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: attempt.inbox, params: callback).perform
    end
    response = Struct.new(:parsed_response).new({ 'messages' => [{ 'id' => id }] })
    response.define_singleton_method(:success?) { true }
    response.define_singleton_method(:code) { 200 }
    response
  end
end
HTTParty.singleton_class.prepend(PrecimechSmokeTransport)

class PrecimechSmokeJobCounter
  def call(_worker, job, _queue)
    klass = job.dig('args', 0, 'job_class')
    if %w[SendReplyJob WhatsappRetryJob].include?(klass)
      Redis.new(url: ENV.fetch('REDIS_URL')).incr("precimech_smoke_#{klass}")
    end
    yield
  end
end
Sidekiq.configure_server { |config| config.server_middleware { |chain| chain.add(PrecimechSmokeJobCounter) } }
