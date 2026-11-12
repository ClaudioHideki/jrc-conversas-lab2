require 'stringio'
require 'json'
require 'timeout'

# Bound the body before Rails/Rack multipart parameter parsing. Other channels
# and routes retain their existing limits and behavior.
# The namespace must exist before this middleware loads during initialization.
# rubocop:disable Style/ClassAndModuleChildren
module JrcBroker
  class HistoryMediaBodyLimit
    LIMIT = (16 * 1024 * 1024) + 65_536
    PATH = %r{\A/api/v1/accounts/[^/]+/jrc_history_sync/v2/inboxes/[^/]+/media}

    def initialize(app)
      @app = app
    end

    # Keep the bounded read and its timeout/error boundary in one method.
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    def call(env)
      # Rails also accepts formats, leading-zero IDs and normalized slashes.
      return @app.call(env) unless env['REQUEST_METHOD'] == 'POST' && PATH.match?(env['PATH_INFO'].to_s.squeeze('/'))

      declared = env['CONTENT_LENGTH'].presence
      return denied(400) if declared && (!/\A\d+\z/.match?(declared) || env['HTTP_TRANSFER_ENCODING'])
      return denied(413) if declared && declared.to_i > LIMIT

      body = +''.b
      input = env['rack.input'] || StringIO.new('')
      Timeout.timeout(10) do
        while (chunk = input.read([8192, LIMIT + 1 - body.bytesize].min)) && !chunk.empty?
          body << chunk
          return denied(413) if body.bytesize > LIMIT
        end
      end
      return denied(400) if declared && declared.to_i != body.bytesize

      env['rack.input'] = StringIO.new(body)
      env['CONTENT_LENGTH'] = body.bytesize.to_s
      @app.call(env)
    rescue IOError
      denied(400)
    rescue Timeout::Error
      denied(408)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    private

    def denied(status)
      [status, { 'Content-Type' => 'application/json', 'Cache-Control' => 'no-store' }, [JSON.generate(error: 'JRC_HISTORY_MEDIA_BODY_INVALID')]]
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
