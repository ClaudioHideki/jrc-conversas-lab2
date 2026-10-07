require 'rails_helper'

RSpec.describe JrcAi::AccountProvider do
  let(:account) { create(:account) }
  let(:other) { create(:account) }
  let!(:provider) do
    JrcAi::Provider.create!(account: account, name: 'Test provider', provider_type: 'openai', default_model: 'test-model',
                            api_key: 'test-account-one-key', active: true, default_provider: true)
  end

  it 'resolves only the authenticated account provider and decrypted credential' do
    JrcAi::Provider.create!(account: other, name: 'Other provider', provider_type: 'openai', default_model: 'other-model',
                            api_key: 'test-account-two-key', active: true, default_provider: true)
    expect(described_class.runtime_configuration(account)).to include(api_key: 'test-account-one-key', model: 'test-model')
    expect(described_class.runtime_configuration(other)).to include(api_key: 'test-account-two-key', model: 'other-model')
  end

  it 'never falls back to a global key or another account when disabled or missing' do
    provider.update!(active: false)
    with_modified_env NICO_PROVIDER_API_KEY: 'test-global-key' do
      expect { described_class.resolve(account) }.to raise_error(JrcNico::RuntimeClient::Error, 'account_ai_not_configured')
      expect { described_class.resolve(other) }.to raise_error(JrcNico::RuntimeClient::Error, 'account_ai_not_configured')
    end
  end

  it 'does not choose another compatible provider behind an explicitly preferred unsupported provider' do
    provider.update!(provider_type: 'anthropic')
    expect { described_class.resolve(account) }.to raise_error(JrcNico::RuntimeClient::Error, 'provider_adapter_unavailable')
  end

  it 'refuses a credential bound to another account and unapproved provider destinations' do
    expect { described_class.runtime_configuration(other, provider: provider) }.to raise_error(JrcNico::RuntimeClient::Error, 'invalid_scope')
    provider.update!(base_url: 'https://unapproved.example.invalid')
    expect { described_class.resolve(account) }.to raise_error(JrcNico::RuntimeClient::Error, 'invalid_configuration')
  end

  it 'passes only the backend-selected account credential to the runtime transport' do
    payload = { account_id: account.id, request_id: SecureRandom.uuid }
    response_body = JSON.parse(Rails.root.join('services/nico-runtime/test/fixtures/operation-contract.json').read)
                        .merge('account_id' => account.id, 'request_id' => payload[:request_id])
    with_modified_env NICO_MODE: 'provider', NICO_RUNTIME_URL: 'http://runtime:3108',
                      NICO_SERVICE_TOKEN: 'isolated-runtime-service-token-for-tests-only' do
      stub_request(:post, 'http://runtime:3108/v1/operate').with do |request|
        body = JSON.parse(request.body)
        expect(body.fetch('provider')).to include('api_key' => 'test-account-one-key', 'model' => 'test-model')
        expect(body.fetch('account_id')).to eq(account.id)
        true
      end.to_return(status: 200, body: response_body.to_json)
      JrcNico::RuntimeClient.new.operate(payload)
      expect(WebMock).to have_requested(:post, 'http://runtime:3108/v1/operate').once
    end
  end

  it 'rejects a provider from another account before any runtime request is made' do
    with_modified_env NICO_MODE: 'provider' do
      client = JrcNico::RuntimeClient.new(provider: provider)
      expect do
        client.operate(account_id: other.id, request_id: SecureRandom.uuid)
      end.to raise_error(JrcNico::RuntimeClient::Error, 'invalid_scope')
      expect(WebMock).not_to have_requested(:post, /runtime/)
    end
  end
end
