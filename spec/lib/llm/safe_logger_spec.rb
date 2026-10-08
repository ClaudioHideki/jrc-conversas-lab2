require 'rails_helper'

RSpec.describe Llm::SafeLogger do
  let(:output) { StringIO.new }
  let(:sink) { Logger.new(output, level: Logger::DEBUG) }
  let(:logger) { described_class.new(sink) }

  it 'is configured once at boot and survives lazy LLM configuration' do
    configured_logger = RubyLLM.logger
    expect(configured_logger).to be_a(described_class)
    Llm::Config.initialize!
    expect(RubyLLM.logger).to equal(configured_logger)
    expect(RubyLLM.config.logger).to equal(configured_logger)
  end

  [
    'Authorization: Bearer test-account-one-key',
    '{"api_key":"test-account-one-key","access_token":"unknown-access-secret","token":"unknown-token-secret"}',
    'Rejected test-account-one-key',
    "X-API-Key: unknown-custom-secret\nCookie: provider-session-secret",
    'GET https://provider.example.invalid?token=unknown-url-secret'
  ].each do |message|
    it "discards sensitive SDK diagnostics #{message.inspect}" do
      logger.debug(message)
      expect(output.string).to include('[RubyLLM] detail=[REDACTED]')
      expect(output.string).not_to include(message, 'test-account-one-key', 'unknown-', 'provider-session-secret')
    end
  end

  it 'discards exception objects and their raw response before logger formatting' do
    error = RubyLLM::UnauthorizedError.new('Rejected test-account-one-key')
    logger.error(error)
    logger.log(Logger::ERROR, error, 'test-account-two-key')
    expect(output.string).to include('[REDACTED]')
    expect(output.string).not_to include('test-account-one-key', 'test-account-two-key')
  end

  it 'does not evaluate a diagnostic block that may expose credentials or raise' do
    logger.debug { raise 'test-account-one-key' }
    expect(output.string).to include('[REDACTED]')
  end

  it 'preserves normal application logs and SDK severity' do
    sink.info('application remains visible')
    logger.warn('provider-secret')
    expect(output.string).to include('application remains visible', 'WARN', '[REDACTED]')
    expect(output.string).not_to include('provider-secret')
  end

  it 'keeps two simultaneous account contexts isolated with one credential-free SDK logger' do
    Llm::Config.initialize!
    system_key = RubyLLM.config.openai_api_key
    expect(RubyLLM).not_to receive(:configure)
    allow(Rails.logger).to receive(:level).and_return(Logger::DEBUG)
    allow(Rails.logger).to receive(:add) do |severity, message, progname, &block|
      sink.add(severity, message, progname, &block)
    end
    credentials = [
      { api_key: 'test-account-one-key', base_url: 'https://account-one.example.invalid/v1', model: 'account-one-model' },
      { api_key: 'test-account-two-key', base_url: 'https://account-two.example.invalid/v1', model: 'account-two-model' }
    ]
    credentials.each do |credential|
      stub_request(:post, "#{credential[:base_url]}/chat/completions")
        .with(headers: { 'Authorization' => "Bearer #{credential[:api_key]}" }) do |request|
          JSON.parse(request.body).fetch('model') == credential[:model]
        end.to_return(status: 401, headers: { 'Content-Type' => 'application/json' },
                      body: { error: { message: 'Rejected test-account-one-key and test-account-two-key', code: 'invalid_api_key' } }.to_json)
    end
    ready = Queue.new
    start = Queue.new
    threads = credentials.map do |credential|
      Thread.new do
        ready << true
        start.pop
        Llm::Config.with_api_key(credential[:api_key], api_base: credential[:base_url]) do |context|
          context.chat(model: credential[:model], provider: :openai, assume_model_exists: true).ask('Test')
        end
      rescue RubyLLM::UnauthorizedError
        :unauthorized
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    expect(threads.map(&:value)).to eq(%i[unauthorized unauthorized])
    expect(output.string).to include('[RubyLLM] detail=[REDACTED]')
    expect(output.string).not_to include('test-account-one-key', 'test-account-two-key')
    expect(RubyLLM.config.openai_api_key).to eq(system_key)
    credentials.each do |credential|
      expect(WebMock).to have_requested(:post, "#{credential[:base_url]}/chat/completions").once
    end
  end
end
