require 'stringio'
require 'json'
require 'timeout'

# Loadable before Zeitwerk; cap bytes before Rack parses multipart or JSON.
# Namespace must exist before this middleware is required during boot.
# rubocop:disable Style/ClassAndModuleChildren
module JrcBroker
  class LiveIngressBodyLimit
    PATH = %r{\A/api/v1/accounts/[^/]+/jrc_broker/inboxes/[^/]+/live-ingress/v1/}
    # UTF-8 content is bounded after JSON decoding. A control byte may occupy
    # six wire bytes (\\u0000), so valid content can exceed its decoded bound.
    JSON_LIMIT = 512 * 1024
    MEDIA_LIMIT = (16 * 1024 * 1024) + JSON_LIMIT

    def initialize(app)
      @app = app
    end

    def call(env)
      return @app.call(env) unless live_request?(env)

      limit = env['CONTENT_TYPE'].to_s.start_with?('multipart/form-data') ? MEDIA_LIMIT : JSON_LIMIT
      body, error = bounded_body(env, limit)
      return denied(error) if error

      env['rack.input'] = StringIO.new(body)
      env['CONTENT_LENGTH'] = body.bytesize.to_s
      @app.call(env)
    rescue IOError
      denied(400)
    rescue Timeout::Error
      denied(408)
    end

    private

    def live_request?(env)
      env['REQUEST_METHOD'] == 'POST' && PATH.match?(env['PATH_INFO'].to_s.squeeze('/'))
    end

    def bounded_body(env, limit)
      declared = env['CONTENT_LENGTH'].presence
      return [nil, 400] if invalid_declared?(env, declared)
      return [nil, 413] if declared && declared.to_i > limit

      body = read_body(env, limit)
      return [nil, 413] if body.bytesize > limit
      return [nil, 400] if declared && declared.to_i != body.bytesize

      [body, nil]
    end

    def invalid_declared?(env, declared)
      declared && (!/\A\d+\z/.match?(declared) || env['HTTP_TRANSFER_ENCODING'])
    end

    def read_body(env, limit)
      body = +''.b
      input = env['rack.input'] || StringIO.new('')
      Timeout.timeout(10) do
        while (chunk = input.read([8192, limit + 1 - body.bytesize].min)) && !chunk.empty?
          body << chunk
          break if body.bytesize > limit
        end
      end
      body
    end

    def denied(status)
      [status, { 'Content-Type' => 'application/json', 'Cache-Control' => 'no-store' }, [JSON.generate(error: 'JRC_LIVE_BODY_INVALID')]]
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
