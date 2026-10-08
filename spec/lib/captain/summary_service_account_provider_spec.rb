require 'rails_helper'

RSpec.describe Captain::SummaryService do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let!(:provider) do
    JrcAi::Provider.create!(account: account, name: 'Account AI', provider_type: 'openai',
                            api_key: 'test-account-one-key', default_model: 'gpt-4.1-mini', default_provider: true)
  end
  let(:service) { described_class.new(account: account, conversation_display_id: 1) }
  let(:messages) { [{ role: 'user', content: 'Summarize this test conversation' }] }
  let(:response) { instance_double(RubyLLM::Message, content: 'Test summary', input_tokens: 30, output_tokens: 10) }
  let(:chat) { instance_double(RubyLLM::Chat, ask: response) }
  let(:context) { instance_double(RubyLLM::Context, chat: chat) }

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-global-key')
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'test-old-hook-key' })
    allow(account).to receive(:feature_enabled?).and_call_original
    allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(true)
    allow(Llm::Config).to receive(:with_api_key).and_yield(context)
  end

  it 'uses the provider key, endpoint and model together, ignoring the old hook and global key' do
    expect(Llm::Config).to receive(:with_api_key).with('test-account-one-key', api_base: 'https://api.openai.com/v1').and_yield(context)
    expect(context).to receive(:chat).with(model: 'gpt-4.1-mini', provider: :openai, assume_model_exists: true).and_return(chat)
    expect(service.send(:make_api_call, feature: 'editor', messages: messages)[:message]).to eq('Test summary')
  end

  it 'resolves different credentials for two accounts' do
    JrcAi::Provider.create!(account: other_account, name: 'Other AI', provider_type: 'openai',
                            api_key: 'test-account-two-key', default_model: 'gpt-4.1-mini', default_provider: true)
    other_service = described_class.new(account: other_account, conversation_display_id: 1)
    expect(service.send(:api_key)).to eq('test-account-one-key')
    expect(other_service.send(:api_key)).to eq('test-account-two-key')
  end

  it 'refuses a missing provider without falling back to another account, the old hook or global key' do
    provider.update!(active: false)
    JrcAi::Provider.create!(account: other_account, name: 'Other AI', provider_type: 'openai',
                            api_key: 'test-account-two-key', default_model: 'gpt-4.1-mini')
    expect(Llm::Config).not_to receive(:with_api_key)
    expect { service.send(:make_api_call, feature: 'editor', messages: messages) }
      .to raise_error(JrcNico::RuntimeClient::Error, 'account_ai_not_configured')
  end

  it 'refuses an unsupported preferred provider without substituting the old hook' do
    provider.update!(provider_type: 'anthropic')
    expect(Llm::Config).not_to receive(:with_api_key)
    expect { service.send(:make_api_call, feature: 'editor', messages: messages) }
      .to raise_error(JrcNico::RuntimeClient::Error, 'provider_adapter_unavailable')
  end

  it 'records actual token usage for this provider without claiming a known monetary cost' do
    service.send(:make_api_call, feature: 'editor', messages: messages)
    event = account.jrc_ai_usage_events.last
    expect(event).to have_attributes(provider_id: provider.id, agent_key: 'copilot', feature: 'summarize',
                                     model: 'gpt-4.1-mini', input_tokens: 30, output_tokens: 10, total_tokens: 40)
    expect(event.metadata).to eq('cost_available' => false)
    expect(other_account.jrc_ai_usage_events).to be_empty
    expect(service.send(:counts_toward_usage?)).to be(false)
  end

  it 'reports rejected credentials without returning or logging private provider details' do
    allow(chat).to receive(:ask).and_raise(RubyLLM::UnauthorizedError.new('PRIVATE_PROVIDER_DETAIL'))
    expect(Rails.logger).to receive(:warn).with("[LLM] account=#{account.id} feature=summarize code=provider_unauthorized")
    result = service.send(:make_api_call, feature: 'editor', messages: messages)
    expect(result).to include(error_code: 'provider_unauthorized')
    expect(result.to_json).not_to include('PRIVATE_PROVIDER_DETAIL', 'test-account-one-key', 'test-old-hook-key')
    expect(account.jrc_ai_usage_events).to be_empty
  end

  it 'sanitizes an unexpected provider failure without exposing prompts or credentials' do
    allow(chat).to receive(:ask).and_raise(StandardError, 'PRIVATE_PROVIDER_DETAIL')
    result = service.send(:make_api_call, feature: 'editor', messages: messages)
    expect(result).to include(error_code: 'provider_unavailable')
    expect(result.to_json).not_to include('PRIVATE_PROVIDER_DETAIL', 'request_messages', 'test-account-one-key')
  end

  it 'keeps the stored key encrypted and leaves credentials out of usage data' do
    provider.reload
    expect(provider.api_key_before_type_cast).not_to include('test-account-one-key')
    expect(provider.api_key).to eq('test-account-one-key')
    service.send(:make_api_call, feature: 'editor', messages: messages)
    expect(account.jrc_ai_usage_events.last.attributes.to_json).not_to include('test-account-one-key', 'test-global-key', 'test-old-hook-key')
  end

  it 'does not expose private information if consumption recording fails' do
    allow(JrcAi::UsageEvent).to receive(:create!).and_raise(StandardError, 'test-account-one-key')
    expect(Rails.logger).to receive(:warn).with("[LLM] account=#{account.id} feature=summarize code=provider_unavailable")
    result = service.send(:make_api_call, feature: 'editor', messages: messages)
    expect(result).to include(error_code: 'provider_unavailable')
    expect(result.to_json).not_to include('test-account-one-key')
  end

  it 'keeps a remote credential error out of telemetry and exception capture' do
    span = instance_double(OpenTelemetry::Trace::Span)
    tracer = instance_double(OpenTelemetry::Trace::Tracer)
    attributes = []
    allow(span).to receive(:set_attribute) { |key, value| attributes << [key, value] }
    allow(span).to receive(:status=) { |status| attributes << ['status', status.description] }
    allow(tracer).to receive(:in_span).and_yield(span)
    allow(service).to receive(:tracer).and_return(tracer)
    allow(ChatwootApp).to receive(:otel_enabled?).and_return(true)
    allow(chat).to receive(:ask).and_raise(RubyLLM::UnauthorizedError.new('test-account-one-key'))
    expect(ChatwootExceptionTracker).not_to receive(:new)
    expect(service.send(:make_api_call, feature: 'editor', messages: messages)).to include(error_code: 'provider_unauthorized')
    expect(attributes.to_json).not_to include('test-account-one-key', 'test-old-hook-key', 'test-global-key')
  end

  Captain::RewriteService::ALLOWED_OPERATIONS.each do |operation|
    it "resolves account key, URL and model for the #{operation} composer action" do
      conversation = create(:conversation, account: account)
      rewrite = Captain::RewriteService.new(account: account, conversation_display_id: conversation.display_id,
                                            content: 'Test draft', operation: operation.to_s)
      allow(chat).to receive(:with_instructions)
      expect(Llm::Config).to receive(:with_api_key).with('test-account-one-key', api_base: 'https://api.openai.com/v1').and_yield(context)
      expect(context).to receive(:chat).with(model: 'gpt-4.1-mini', provider: :openai, assume_model_exists: true).and_return(chat)
      expect(rewrite.perform[:message]).to eq('Test summary')
    end
  end

  it 'preserves the account feature flag and makes no provider request when disabled' do
    allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(false)
    expect(Llm::Config).not_to receive(:with_api_key)
    expect(service.send(:make_api_call, feature: 'editor', messages: messages)).to include(error_code: 403)
  end

  it 'supports the configured OpenAI-compatible endpoint and custom model without global overrides' do
    provider.update!(provider_type: 'custom', base_url: 'https://account-ai.example.invalid/v1', default_model: 'test-custom-model')
    with_modified_env NICO_PROVIDER_ALLOWED_HOSTS: 'account-ai.example.invalid' do
      expect(Llm::Config).to receive(:with_api_key).with('test-account-one-key', api_base: 'https://account-ai.example.invalid/v1').and_yield(context)
      expect(context).to receive(:chat).with(model: 'test-custom-model', provider: :openai, assume_model_exists: true).and_return(chat)
      expect(service.send(:make_api_call, feature: 'editor', messages: messages)[:message]).to eq('Test summary')
    end
  end

  it 'does not expose an echoed credential through the SDK logger even at DEBUG level' do
    allow(Llm::Config).to receive(:with_api_key).and_call_original
    output = StringIO.new
    sdk_logger = Logger.new(output)
    sdk_logger.level = Logger::DEBUG
    expect(RubyLLM.logger).to be_a(Llm::SafeLogger)
    allow(Rails.logger).to receive(:level).and_return(Logger::DEBUG)
    allow(Rails.logger).to receive(:add) do |severity, message, progname, &block|
      sdk_logger.add(severity, message, progname, &block)
    end
    expect(Rails.logger).to receive(:warn).with("[LLM] account=#{account.id} feature=summarize code=provider_unauthorized").and_call_original
    stub_request(:post, 'https://api.openai.com/v1/chat/completions')
      .with(headers: { 'Authorization' => 'Bearer test-account-one-key' })
      .to_return(status: 401, headers: { 'Content-Type' => 'application/json' },
                 body: { error: { message: 'Rejected test-account-one-key', type: 'invalid_request_error', code: 'invalid_api_key' } }.to_json)

    result = service.send(:make_api_call, feature: 'editor', messages: messages)
    expect(result).to include(error_code: 'provider_unauthorized')
    expect(result.to_json).not_to include('test-account-one-key')
    expect(output.string).not_to include('test-account-one-key')
    expect(output.string).to include('[RubyLLM] detail=[REDACTED]')
  end
end
