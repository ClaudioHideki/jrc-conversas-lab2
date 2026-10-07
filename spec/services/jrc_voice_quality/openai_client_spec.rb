require 'rails_helper'

RSpec.describe JrcVoiceQuality::OpenaiClient do
  let(:account) { create(:account) }
  let(:client) { described_class.new(account: account) }
  let!(:provider) do
    JrcAi::Provider.create!(account: account, name: 'Voice test', provider_type: 'openai',
                            default_model: 'account-voice-model', api_key: 'test-voice-account-key', active: true, default_provider: true)
  end

  it 'uses the account key, model and transcription model instead of a global credential' do
    provider.update!(settings: { transcription_model: 'account-transcription-model' })
    with_modified_env OPENAI_API_KEY: 'test-global-key' do
      expect(client.configured?).to be(true)
      expect(client.send(:api_key)).to eq('test-voice-account-key')
      expect(client.analysis_model).to eq('account-voice-model')
      expect(client.transcription_model).to eq('account-transcription-model')
    end
  end

  it 'does not use another account provider or the global key when this account has no active provider' do
    provider.update!(active: false)
    JrcAi::Provider.create!(account: create(:account), name: 'Other', provider_type: 'openai',
                            default_model: 'other-model', api_key: 'test-other-account-key', active: true)
    with_modified_env OPENAI_API_KEY: 'test-global-key' do
      expect(client.configured?).to be(false)
      expect { client.analyze!('Texto de teste') }.to raise_error(JrcVoiceQuality::AnalysisError, /Provedor de IA da conta/)
    end
  end

  it 'sends voice analysis through the account provider and preserves the report transcript' do
    transcript = 'Cliente: obrigado. Operador: estou à disposição.'
    analysis = JrcVoiceQuality::LocalAnalyzer.new(transcript).call
    stub_request(:post, 'https://api.openai.com/v1/chat/completions')
      .with(headers: { 'Authorization' => 'Bearer test-voice-account-key' }) do |request|
        body = JSON.parse(request.body)
        expect(body.fetch('model')).to eq('account-voice-model')
        expect(body.fetch('messages').last.fetch('content')).to include(transcript)
        true
      end.to_return(status: 200, body: { choices: [{ message: { content: analysis.to_json } }] }.to_json)
    result = client.analyze!(transcript)
    expect(result.fetch('texto_transcrito')).to eq(transcript)
    expect(result).to include('sentimento_cliente', 'sentimento_atendente', 'avaliacao_atendente')
  end
end
