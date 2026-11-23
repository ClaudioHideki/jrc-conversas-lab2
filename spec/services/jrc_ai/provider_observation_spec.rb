require 'rails_helper'

RSpec.describe JrcAi::ProviderObservation do
  let(:account) { create(:account) }
  let(:provider) do
    JrcAi::Provider.create!(account: account, name: 'Test', provider_type: 'custom', api_key: 'local-test-only',
                            default_model: 'test-model', settings: { usage_policy: 'provider' })
  end
  let(:input) { { 'account_id' => account.id, 'request_id' => 'test-request' } }
  let(:observation) do
    input.merge('http_status' => 429, 'headers' => { 'x-ratelimit-limit-tokens' => '8000', 'retry-after' => '12' })
  end

  it 'records provider metadata separately from token usage and never claims a balance' do
    expect { described_class.record!(observation, input: input, provider: provider) }.not_to change(JrcAi::UsageEvent, :count)
    expect(provider.reload.settings).to include('usage_policy' => 'provider')
    expect(provider.settings['provider_observation']).to include('http_status' => 429, 'headers' => observation['headers'],
                                                                'balance_available' => false, 'source' => 'provider_response')
  end

  it 'rejects another account or request without changing the selected provider' do
    [observation.merge('account_id' => account.id + 1), observation.merge('request_id' => 'other')].each do |value|
      expect { described_class.record!(value, input: input, provider: provider) }.to raise_error(JrcNico::RuntimeClient::Error)
    end
    expect(provider.reload.settings).not_to have_key('provider_observation')
  end

  it 'rejects unknown headers and unsafe header values' do
    [{ 'authorization' => 'PRIVATE' }, { 'retry-after' => '<unsafe>' }].each do |headers|
      expect { described_class.record!(observation.merge('headers' => headers), input: input, provider: provider) }
        .to raise_error(JrcNico::RuntimeClient::Error)
    end
  end

  it 'keeps older runtimes compatible without inventing observed limits' do
    described_class.record!(nil, input: input, provider: provider)
    expect(provider.reload.settings).not_to have_key('provider_observation')
  end
end
