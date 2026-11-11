require '/app/config/environment'
require 'json'

# Test transport only, mounted read-only at runtime; never copied into the image.
module PrecimechSmokeTransport
  def post(url, options = {})
    raise 'Unexpected smoke transport URL' unless url == 'https://graph.facebook.com/v13.0/123456789/messages'

    body = JSON.parse(options.fetch(:body))
    raise 'Expected pt_BR template, not a session message' unless body['type'] == 'template' &&
                                                               body.dig('template', 'language', 'code') == 'pt_BR'
    raise 'Unexpected template name' unless body.dig('template', 'name') == 'reativacao_cliente_01'
    raise 'Unexpected parameters' unless body.dig('template', 'components', 0, 'parameters', 0, 'text') == 'Synthetic'

    Redis.new(url: ENV.fetch('REDIS_URL')).incr('precimech_smoke_posts')
    response = Struct.new(:parsed_response).new({ 'messages' => [{ 'id' => 'wamid.synthetic-image' }] })
    response.define_singleton_method(:success?) { true }
    response
  end
end
HTTParty.singleton_class.prepend(PrecimechSmokeTransport)

class PrecimechSmokeJobCounter
  def call(_worker, job, _queue)
    if job.dig('args', 0, 'job_class') == 'SendReplyJob'
      Redis.new(url: ENV.fetch('REDIS_URL')).incr('precimech_smoke_send_reply_jobs')
    end
    yield
  end
end
Sidekiq.configure_server do |config|
  config.server_middleware { |chain| chain.add(PrecimechSmokeJobCounter) }
end
