require 'rails_helper'

RSpec.describe JrcNico::OperationalInference do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let!(:provider) do
    JrcAi::Provider.create!(account: account, name: 'Test', provider_type: 'openai', default_model: 'test-model',
                           api_key: 'test-key-not-real', active: true, default_provider: true)
  end
  let(:payload_id) { SecureRandom.uuid }
  let(:wire) do
    JSON.parse(Rails.root.join('services/nico-runtime/test/fixtures/operation-contract.json').read)
        .merge('account_id' => account.id, 'request_id' => payload_id)
  end
  let(:payload) { { account_id: account.id, request_id: payload_id, kind: 'operator', message: 'Read only fixture', context: {}, history: [] } }
  around do |example|
    with_modified_env NICO_MODE: 'provider', NICO_RUNTIME_URL: 'http://runtime:3108',
                      NICO_SERVICE_TOKEN: 'isolated-service-token-for-local-tests-only' do
      example.run
    end
  end

  # Real client and reservation lifecycle, only the HTTP transport is simulated.
  def call_operation
    described_class.metered(account: account, user: user, kind: 'operator', reservation_tokens: 1000, request_id: payload_id) do |selected, ledger|
      expect(selected.id).to eq(provider.id)
      JrcNico::RuntimeClient.new(provider: selected, ledger: ledger).operate(payload)
    end
  end

  it 'accounts a successful runtime response exactly once and only on the selected account provider' do
    stub_request(:post, 'http://runtime:3108/v1/operate').with do |request|
      body = JSON.parse(request.body)
      body['account_id'] == account.id && body.dig('provider', 'api_key') == 'test-key-not-real'
    end.to_return(status: 200, body: wire.to_json)
    expect(call_operation['usage']['total_tokens']).to eq(30)
    expect(JrcNico::Inference.last).to have_attributes(status: 'completed', reserved_tokens: 0)
    expect(account.jrc_ai_usage_events.last).to have_attributes(provider_id: provider.id, total_tokens: 30)
    expect(WebMock).to have_requested(:post, 'http://runtime:3108/v1/operate').once
  end

  [['401', 'unauthorized'], ['403', 'account_not_configured'], ['429', 'runtime_busy'], ['422', 'account_ai_not_configured']].each do |status, code|
    it "releases the reservation on a proven pre-engine #{status} #{code} rejection" do
      stub_request(:post, 'http://runtime:3108/v1/operate').to_return(status: status.to_i, body: { error: code }.to_json)
      expect { call_operation }.to raise_error(JrcNico::RuntimeClient::Error) { |error| expect(error.code).to eq(code) }
      expect(JrcNico::Inference.last).to have_attributes(status: 'failed', reserved_tokens: 0)
      expect(account.jrc_ai_usage_events).to be_empty
    end
  end

  [[401, 'provider_unauthorized'], [403, 'provider_forbidden'], [429, 'provider_rate_limited'],
   [429, 'provider_quota_exceeded'], [502, 'provider_unavailable'], [504, 'provider_timeout']].each do |status, code|
    it "retains uncertainty on #{status} #{code}, which may follow a billed repair attempt" do
      stub_request(:post, 'http://runtime:3108/v1/operate').to_return(status: status, body: { error: code }.to_json)
      expect { call_operation }.to raise_error(JrcNico::RuntimeClient::Error) { |error| expect(error.code).to eq(code) }
      expect(JrcNico::Inference.last).to have_attributes(status: 'unknown', reserved_tokens: 1000)
      expect(account.jrc_ai_usage_events).to be_empty
      expect(WebMock).to have_requested(:post, 'http://runtime:3108/v1/operate').once
    end
  end

  it 'releases a configuration failure before POST and never leaks the service credential' do
    with_modified_env NICO_RUNTIME_URL: 'ftp://invalid' do
      expect { call_operation }.to raise_error(JrcNico::RuntimeClient::Error, 'invalid_configuration')
      expect(JrcNico::Inference.last).to have_attributes(status: 'failed', reserved_tokens: 0)
      expect(WebMock).not_to have_requested(:post, 'http://runtime:3108/v1/operate')
    end
  end

  it 'retains unknown consumption on a transport timeout after dispatch' do
    stub_request(:post, 'http://runtime:3108/v1/operate').to_timeout
    expect { call_operation }.to raise_error(JrcNico::RuntimeClient::Error, 'runtime_timeout')
    expect(JrcNico::Inference.last).to have_attributes(status: 'unknown', reserved_tokens: 1000)
  end

  it 'records a scoped valid receipt even when malformed output prevents executing a tool' do
    stub_request(:post, 'http://runtime:3108/v1/operate').to_return(status: 200, body: wire.merge('arguments' => '{').to_json)
    expect { call_operation }.to raise_error(JrcNico::RuntimeClient::Error, 'tool_arguments_invalid')
    expect(JrcNico::Inference.last).to have_attributes(status: 'failed', reserved_tokens: 0)
    expect(account.jrc_ai_usage_events.sum(:total_tokens)).to eq(30)
  end

  context 'with terminal runtime accounting' do
    let(:receipt) do
      { 'version' => 1, 'complete' => true, 'attempts' => 2, 'request_id' => payload_id, 'account_id' => account.id,
        'mode' => 'provider', 'model' => 'test-model', 'usage' => { 'input_tokens' => 20, 'output_tokens' => 10, 'total_tokens' => 30 } }
    end

    it 'records complete failed-attempt usage once without changing unrelated unknown reservations or exposing an action' do
      unknown = JrcNico::Inference.create!(account: account, user: user, status: 'unknown', reserved_tokens: 500)
      before = unknown.attributes
      stub_request(:post, 'http://runtime:3108/v1/operate')
        .to_return(status: 502, body: { error: 'tool_arguments_invalid', accounting: receipt }.to_json)

      expect { call_operation }.to raise_error(JrcNico::RuntimeClient::Error, 'tool_arguments_invalid')
      inference = JrcNico::Inference.where.not(id: unknown.id).sole
      expect(inference).to have_attributes(status: 'failed', reserved_tokens: 0)
      expect(account.jrc_ai_usage_events.sole).to have_attributes(total_tokens: 30, provider_id: provider.id)

      ledger = JrcNico::ReservationLedger.new(inference)
      ledger.receipt!(receipt)
      ledger.failed!(JrcNico::RuntimeClient::Error.new('tool_arguments_invalid'))
      expect(account.jrc_ai_usage_events.count).to eq(1)
      expect(unknown.reload.attributes).to eq(before)
      expect(JrcNico::RunCapacity.snapshot(account)).to include(used_tokens: 30, reserved_tokens: 500)
      expect(WebMock).to have_requested(:post, 'http://runtime:3108/v1/operate').once
    end

    it 'keeps an explicitly estimated terminal receipt counted and labelled estimated' do
      stub_request(:post, 'http://runtime:3108/v1/operate')
        .to_return(status: 502, body: { error: 'provider_schema_invalid', accounting: receipt.merge('usage_estimated' => true) }.to_json)
      expect { call_operation }.to raise_error(JrcNico::RuntimeClient::Error, 'provider_schema_invalid')
      expect(JrcNico::Inference.last).to have_attributes(status: 'failed', reserved_tokens: 0)
      expect(JrcNico::Inference.last.accounting['basis']).to eq('estimated')
      expect(account.jrc_ai_usage_events.sole.metadata['usage_estimated']).to be(true)
    end

    it 'rejects a complete receipt from another existing Account without charging either tenant' do
      foreign = create(:account)
      stub_request(:post, 'http://runtime:3108/v1/operate')
        .to_return(status: 502, body: { error: 'tool_arguments_invalid', accounting: receipt.merge('account_id' => foreign.id) }.to_json)
      expect { call_operation }.to raise_error(JrcNico::RuntimeClient::Error)
      expect(JrcNico::Inference.last).to have_attributes(status: 'unknown', reserved_tokens: 1000)
      expect(JrcAi::UsageEvent.where(account: [account, foreign])).to be_empty
    end

    {
      'foreign request' => { 'request_id' => '6c3aebf4-777a-4847-b4dc-4c828bcc47c5' },
      'incomplete attempts' => { 'complete' => false }, 'missing complete proof' => { 'complete' => nil },
      'future version' => { 'version' => 2 }, 'non-integer version' => { 'version' => 1.0 },
      'excessive attempts' => { 'attempts' => 3 }, 'zero attempts' => { 'attempts' => 0 },
      'non-integer attempts' => { 'attempts' => 2.0 }, 'wrong provider model' => { 'model' => 'other-model' },
      'fixture mode' => { 'mode' => 'fixture' }, 'invalid estimate marker' => { 'usage_estimated' => false },
      'null estimate marker' => { 'usage_estimated' => nil },
      'invalid usage total' => { 'usage' => { 'input_tokens' => 20, 'output_tokens' => 10, 'total_tokens' => 31 } },
      'extra output fields' => { 'arguments' => '{}' }
    }.each do |description, change|
      it "retains the full hold on #{description} in an error receipt" do
        stub_request(:post, 'http://runtime:3108/v1/operate')
          .to_return(status: 502, body: { error: 'tool_arguments_invalid', accounting: receipt.merge(change) }.to_json)
        expect { call_operation }.to raise_error(JrcNico::RuntimeClient::Error)
        expect(JrcNico::Inference.last).to have_attributes(status: 'unknown', reserved_tokens: 1000)
        expect(account.jrc_ai_usage_events).to be_empty
      end
    end

    it 'never accepts a partial first receipt after a later timeout' do
      stub_request(:post, 'http://runtime:3108/v1/operate')
        .to_return(status: 504, body: { error: 'provider_timeout', accounting: receipt }.to_json)
      expect { call_operation }.to raise_error(JrcNico::RuntimeClient::Error)
      expect(JrcNico::Inference.last).to have_attributes(status: 'unknown', reserved_tokens: 1000)
      expect(account.jrc_ai_usage_events).to be_empty
    end
  end

  it 'does not trust a receipt from another account or an invalid estimation flag' do
    [wire.merge('account_id' => account.id + 1), wire.merge('usage_estimated' => 'true')].each do |response_body|
      stub_request(:post, 'http://runtime:3108/v1/operate').to_return(status: 200, body: response_body.to_json)
      expect { call_operation }.to raise_error(JrcNico::RuntimeClient::Error)
    end
    expect(account.jrc_ai_usage_events).to be_empty
    expect(JrcNico::Inference.where(account: account).pluck(:reserved_tokens)).to eq([1000, 1000])
  end

  it 'retains unknown usage after a non-JSON upstream 5xx instead of claiming zero' do
    stub_request(:post, 'http://runtime:3108/v1/operate').to_return(status: 502, body: '<html>PRIVATE proxy response</html>')
    expect { call_operation }.to raise_error(JrcNico::RuntimeClient::Error) { |error| expect(error.user_message).not_to include('PRIVATE') }
    expect(JrcNico::Inference.last).to have_attributes(status: 'unknown', reserved_tokens: 1000)
  end

  it 'does not admit or POST work when this account has no configured provider' do
    provider.update!(active: false)
    expect { call_operation }.to raise_error(JrcNico::RuntimeClient::Error, 'account_ai_not_configured')
    expect(JrcNico::Inference.where(account: account)).to be_empty
    expect(WebMock).not_to have_requested(:post, 'http://runtime:3108/v1/operate')
  end
end
