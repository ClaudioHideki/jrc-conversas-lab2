require 'rails_helper'

RSpec.describe Captain::CsatUtilityAnalysisService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account, message: 'Test message', language: 'en', baseline: {}) }

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
    JrcAi::Provider.create!(account: account, name: 'Account AI', provider_type: 'openai',
                            api_key: 'test-account-key', default_model: 'gpt-4.1-mini', default_provider: true)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
  end

  describe '#perform' do
    before do
      allow(account).to receive(:feature_enabled?).and_call_original
      allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(true)
      allow(service).to receive(:make_api_call).and_return({
                                                             message: '{"classification":"LIKELY_UTILITY","optimized_message":"Utility-safe message"}'
                                                           })
    end

    it 'returns parsed payload and preserves raw message for usage metering' do
      result = service.perform

      expect(result[:classification]).to eq('LIKELY_UTILITY')
      expect(result[:optimized_message]).to eq('Utility-safe message')
      expect(result[:message]).to eq('{"classification":"LIKELY_UTILITY","optimized_message":"Utility-safe message"}')
    end

    it 'routes through the editor feature' do
      expect(service).to receive(:make_api_call).with(
        hash_including(feature: 'editor')
      ).and_return({ message: '{"classification":"LIKELY_UTILITY"}' })

      service.perform
    end
  end

  describe '#api_key' do
    context 'when account has an OpenAI hook key' do
      before do
        create(:integrations_hook, :openai, account: account, settings: { 'api_key' => 'customer-own-key' })
      end

      it 'uses the account provider instead of the old hook key' do
        expect(service.send(:api_key)).to eq('test-account-key')
      end
    end

    context 'when account does not have an OpenAI hook key' do
      it 'uses the account provider without requiring an OpenAI hook' do
        expect(service.send(:api_key)).to eq('test-account-key')
      end
    end
  end
end
