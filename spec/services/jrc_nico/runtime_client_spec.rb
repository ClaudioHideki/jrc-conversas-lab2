require 'rails_helper'

RSpec.describe JrcNico::RuntimeClient do
  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:conversation) { create(:conversation, account: account) }
  let(:run) { JrcNico::Run.create!(account: account, user: user, conversation: conversation, request_id: SecureRandom.uuid, message: 'Resumo') }
  let(:context) { { conversation: [{ source: 'conversation', reference: 'message:1', text: 'Olá' }], crm: [], knowledge: [] } }
  let(:body) do
    { request_id: run.request_id, account_id: account.id, summary: 'Resumo', suggested_reply: 'Olá',
      evidence: [{ source: 'conversation', reference: 'message:1' }], warnings: [], usage: nil, model: 'fixture-local', mode: 'fixture' }
  end

  it 'sends service credentials and rejects invented citations' do
    with_modified_env NICO_RUNTIME_URL: 'http://runtime:3108', NICO_SERVICE_TOKEN: 'local-test-token-only-not-for-production' do
      stub_request(:post, 'http://runtime:3108/v1/analyze').with(headers: { 'Authorization' => 'Bearer local-test-token-only-not-for-production' })
                                                          .to_return(status: 200, body: body.merge(evidence: [{ source: 'crm', reference: 'deal:999' }]).to_json)
      expect { described_class.new.analyze(run, context) }.to raise_error { |error| expect(error.class.name).to eq('JrcNico::RuntimeClient::Error') }
    end
  end

  it 'rejects a valid-looking response from another account' do
    with_modified_env NICO_RUNTIME_URL: 'http://runtime:3108', NICO_SERVICE_TOKEN: 'local-test-token-only-not-for-production' do
      stub_request(:post, 'http://runtime:3108/v1/analyze').to_return(status: 200, body: body.merge(account_id: account.id + 1).to_json)
      expect { described_class.new.analyze(run, context) }.to raise_error { |error| expect(error.class.name).to eq('JrcNico::RuntimeClient::Error') }
    end
  end

  it 'preserves explicit simulation status and absent real token usage' do
    with_modified_env NICO_RUNTIME_URL: 'http://runtime:3108', NICO_SERVICE_TOKEN: 'local-test-token-only-not-for-production' do
      stub_request(:post, 'http://runtime:3108/v1/analyze').to_return(status: 200, body: body.to_json)
      expect(described_class.new.analyze(run, context)).to include('mode' => 'fixture', 'usage' => nil)
    end
  end

  describe 'server-owned Account routing' do
    let(:other_account) { create(:account) }
    let(:routes) do
      {
        account.id.to_s => { url: 'http://nico-a:3108', token_env: 'NICO_RUNTIME_TOKEN_A' },
        other_account.id.to_s => { url: 'http://nico-b:3108', token_env: 'NICO_RUNTIME_TOKEN_B' }
      }.to_json
    end

    around do |example|
      with_modified_env NICO_RUNTIME_ROUTES: routes,
                        NICO_RUNTIME_TOKEN_A: 'account-a-test-token-not-for-production',
                        NICO_RUNTIME_TOKEN_B: 'account-b-test-token-not-for-production',
                        NICO_RUNTIME_URL: 'http://legacy:3108', NICO_SERVICE_TOKEN: 'legacy-test-token-not-for-production' do
        example.run
      end
    end

    it 'sends each Account only to its configured runtime with its own credential' do
      other_user = create(:user, account: other_account, role: :administrator)
      other_run = JrcNico::Run.create!(account: other_account, user: other_user,
                                      conversation: create(:conversation, account: other_account),
                                      request_id: SecureRandom.uuid, message: 'Resumo')
      stub_request(:post, 'http://nico-a:3108/v1/analyze')
        .with(headers: { 'Authorization' => 'Bearer account-a-test-token-not-for-production' },
              body: hash_including('account_id' => account.id))
        .to_return(status: 200, body: body.to_json)
      stub_request(:post, 'http://nico-b:3108/v1/analyze')
        .with(headers: { 'Authorization' => 'Bearer account-b-test-token-not-for-production' },
              body: hash_including('account_id' => other_account.id))
        .to_return(status: 200, body: body.merge(account_id: other_account.id, request_id: other_run.request_id).to_json)

      expect(described_class.new.analyze(run, context)['account_id']).to eq(account.id)
      expect(described_class.new.analyze(other_run, context)['account_id']).to eq(other_account.id)
      expect(WebMock).not_to have_requested(:post, 'http://legacy:3108/v1/analyze')
    end

    it 'fails closed for an unmapped Account instead of using the global fallback' do
      with_modified_env NICO_RUNTIME_ROUTES: {}.to_json do
        expect { described_class.new.analyze(run, context) }.to raise_error(described_class::Error) { |error| expect(error.code).to eq('account_not_configured') }
        expect(WebMock).not_to have_requested(:post, 'http://legacy:3108/v1/analyze')
      end
    end

    it 'still rejects a response containing a different Account from the selected runtime' do
      stub_request(:post, 'http://nico-a:3108/v1/analyze')
        .to_return(status: 200, body: body.merge(account_id: other_account.id).to_json)
      expect { described_class.new.analyze(run, context) }.to raise_error(described_class::Error)
    end

    it 'rejects invalid routing configuration without leaking its contents' do
      ['{PRIVATE_CONFIG', '[]', { account.id.to_s => { url: 'http://nico-a:3108', token_env: 'DATABASE_PASSWORD' } }.to_json].each do |config|
        with_modified_env NICO_RUNTIME_ROUTES: config do
          expect { described_class.new.analyze(run, context) }.to raise_error do |error|
            expect(error.code).to eq('invalid_configuration')
            expect(error.message).not_to include('PRIVATE_CONFIG', 'DATABASE_PASSWORD')
          end
        end
      end
    end
  end

  describe 'operation wire contract' do
    let(:wire) { JSON.parse(Rails.root.join('services/nico-runtime/test/fixtures/operation-contract.json').read) }
    let(:payload) { { request_id: wire['request_id'], account_id: wire['account_id'], kind: 'operator', message: 'Criar Telmo', context: {}, history: [] } }

    around do |example|
      with_modified_env NICO_RUNTIME_URL: 'http://runtime:3108', NICO_SERVICE_TOKEN: 'PRIVATE_SERVICE_TOKEN_TEST_12345678' do
        example.run
      end
    end

    it 'accepts the same fixture validated by TypeScript, including aggregated usage' do
      stub_request(:post, 'http://runtime:3108/v1/operate').to_return(status: 200, body: wire.to_json)
      result = described_class.new.operate(payload)
      expect(result['arguments']).to eq('name' => 'Telmo Miranda', 'phone_number' => '+5511991234567')
      expect(result['usage']['total_tokens']).to eq(30)
    end

    it 'preserves the explicit estimated-usage marker and rejects invalid markers' do
      stub_request(:post, 'http://runtime:3108/v1/operate').to_return(status: 200, body: wire.merge('usage_estimated' => true).to_json)
      expect(described_class.new.operate(payload)['usage_estimated']).to be(true)
      stub_request(:post, 'http://runtime:3108/v1/operate').to_return(status: 200, body: wire.merge('usage_estimated' => 'true').to_json)
      expect { described_class.new.operate(payload) }.to raise_error { |error| expect(error.code).to eq('invalid_response') }
    end

    it 'rejects malformed, oversized, deeply nested, primitive and array arguments' do
      ['{', 'null', '[]', '42', '"text"', { x: 'á' * 6000 }.to_json, '{"x":' * 9 + '0' + '}' * 9,
       '{"id":9007199254740993}'].each do |arguments|
        stub_request(:post, 'http://runtime:3108/v1/operate').to_return(status: 200, body: wire.merge('arguments' => arguments).to_json)
        expect { described_class.new.operate(payload) }.to raise_error { |error| expect(error.class.name).to eq('JrcNico::RuntimeClient::Error') }
      end
    end

    %w[provider_outer_json_invalid tool_arguments_invalid provider_schema_invalid provider_timeout provider_unauthorized
       provider_forbidden provider_rate_limited provider_unavailable runtime_busy account_not_configured unauthorized].each do |code|
      it "preserves #{code} without repeating the Rails request" do
        stub_request(:post, 'http://runtime:3108/v1/operate').to_return(status: 502, body: { error: code }.to_json)
        expect { described_class.new.operate(payload) }.to raise_error { |error| expect(error.code).to eq(code) }
        expect(WebMock).to have_requested(:post, 'http://runtime:3108/v1/operate').once
      end
    end

    it 'distinguishes a Rails transport timeout from a provider timeout' do
      stub_request(:post, 'http://runtime:3108/v1/operate').to_timeout
      expect { described_class.new.operate(payload) }.to raise_error { |error| expect(error.code).to eq('runtime_timeout') }
      stub_request(:post, 'http://runtime:3108/v1/operate').to_raise(Errno::ECONNREFUSED)
      expect { described_class.new.operate(payload) }.to raise_error { |error| expect(error.code).to eq('runtime_transport_error') }
    end

    it 'never logs credentials or untrusted error bodies' do
      lines = []
      allow(Rails.logger).to receive(:warn) { |line| lines << line }
      secret = 'Authorization PRIVATE_SERVICE_TOKEN_TEST_12345678 PRIVATE_OPENAI_KEY PRIVATE_CONVERSATION'
      stub_request(:post, 'http://runtime:3108/v1/operate').to_return(status: 502, body: { error: secret }.to_json)
      expect { described_class.new.operate(payload) }.to raise_error { |error| expect(error.code).to eq('runtime_transport_error') }
      expect(lines.join).to include('code=runtime_transport_error')
      expect(lines.join).not_to include('Authorization', 'PRIVATE_SERVICE_TOKEN', 'PRIVATE_OPENAI_KEY', 'PRIVATE_CONVERSATION')
    end
  end

end
