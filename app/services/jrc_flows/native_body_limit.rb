require 'stringio'
require 'json'
require 'timeout'
require_relative 'native_editor_operation'

module JrcFlows
  class NativeBodyLimit
    def initialize(app)
      @app = app
    end

    def call(env)
      path = env['PATH_INFO'].to_s
      unless path.start_with?('/api/v1/jrc_flow_native/') || %r{\A/api/v1/accounts/[1-9][0-9]*/jrc_flow_delegation(?:/|\z)}.match?(path)
        return @app.call(env)
      end

      limit = path.end_with?('/registration-challenge') || %r{/jrc_flow_delegation/registration(?:/|\z)}.match?(path) ? 65_536 : 16_384
      limit = JrcFlows::NativeEditorOperation::GRAPH_LIMIT if JrcFlows::NativeEditorOperation.graph_request?(env['REQUEST_METHOD'], path)
      uuid = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}'
      media = env['REQUEST_METHOD'] == 'POST' &&
              %r{\A/api/v1/accounts/[1-9][0-9]*/jrc_flow_delegation/sessions/#{uuid}/flows/#{uuid}/channels/#{uuid}/media\z}.match?(path)
      if media
        return denied(415, 'FLOW_INVALID_REQUEST') unless env['CONTENT_TYPE'] == 'application/octet-stream'

        limit = 16 * 1024 * 1024
      end
      declared = env['CONTENT_LENGTH']
      declared = nil if declared == ''
      return denied(400, 'FLOW_INVALID_REQUEST') if declared && !/\A[0-9]+\z/.match?(declared)
      return denied(400, 'FLOW_INVALID_REQUEST') if declared && env['HTTP_TRANSFER_ENCODING']
      return denied(413, 'FLOW_REQUEST_TOO_LARGE') if declared && declared.to_i > limit

      body = +''
      input = env['rack.input'] || StringIO.new('')
      Timeout.timeout(10) do
        while (chunk = input.read([8192, limit + 1 - body.bytesize].min)) && !chunk.empty?
          body << chunk
          return denied(413, 'FLOW_REQUEST_TOO_LARGE') if body.bytesize > limit
        end
      end
      return denied(400, 'FLOW_INVALID_REQUEST') if declared && declared.to_i != body.bytesize

      env['rack.input'] = StringIO.new(body)
      env['CONTENT_LENGTH'] = body.bytesize.to_s
      status, headers, response = @app.call(env)
      [status, headers.merge('Cache-Control' => 'no-store', 'Pragma' => 'no-cache'), response]
    rescue IOError
      denied(400, 'FLOW_INVALID_REQUEST')
    rescue Timeout::Error
      denied(408, 'FLOW_REQUEST_TIMEOUT')
    end

    private

    def denied(status, code)
      [status, { 'Content-Type' => 'application/json', 'Cache-Control' => 'no-store', 'Pragma' => 'no-cache' }, [JSON.generate(code: code)]]
    end
  end
end
