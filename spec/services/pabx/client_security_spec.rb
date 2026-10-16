require 'rails_helper'
require 'stringio'

RSpec.describe Pabx::Client, :pabx do
  let(:integration) do
    create(:telephony_integration, history_enabled: false, pabx_settings: pabx_settings(enabled: false, sync_enabled: false),
           pabx_username: 'synthetic@example.test', pabx_password: 'synthetic-api-password')
  end
  let(:client) { described_class.new(integration) }
  let(:login_url) { 'https://pbx.example.test/api/v1/auth/login' }
  let(:url) { 'https://pbx.example.test/api/v1/admin/dids' }

  before do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(Resolv).to receive(:getaddresses).with('pbx.example.test').and_return(['93.184.216.34'])
    stub_request(:post, login_url)
      .with(body: { email: 'synthetic@example.test', password: 'synthetic-api-password' }.to_json)
      .to_return(body: { token: 'synthetic-bearer' }.to_json)
    stub_request(:get, url).to_return(body: '[]')
  end

  it 'reuses the encrypted Account cache across separate Client instances' do
    client.request(:get, '/api/v1/admin/dids')
    reread = TelephonyIntegration.find(integration.id)
    expect(reread.pabx_settings).to eq(integration.pabx_settings)
    expect(Pabx::Settings.new(reread).fingerprint).to eq(Pabx::Settings.new(integration).fingerprint)
    described_class.new(reread).request(:get, '/api/v1/admin/dids')
    expect(a_request(:post, login_url)).to have_been_made.once
    expect(Rails.cache.read(client.send(:cache_key)).include?('synthetic-bearer')).to be(false)
    expect(integration.reload.pabx_settings).to include('enabled' => false, 'sync_enabled' => false)
  end

  it 'expires the shared cache after five minutes for subsequent Client instances' do
    client.request(:get, '/api/v1/admin/dids')
    travel 6.minutes do
      described_class.new(TelephonyIntegration.find(integration.id)).request(:get, '/api/v1/admin/dids')
    end
    expect(a_request(:post, login_url)).to have_been_made.twice
  end

  it 'uses freshly persisted credentials rather than the previous configuration token' do
    client.request(:get, '/api/v1/admin/dids')
    integration.update!(pabx_password: 'block2b-rotated')
    rotated = stub_request(:post, login_url)
              .with(body: { email: 'synthetic@example.test', password: 'block2b-rotated' }.to_json)
              .to_return(body: { token: 'synthetic-bearer' }.to_json)
    described_class.new(TelephonyIntegration.find(integration.id)).request(:get, '/api/v1/admin/dids')
    expect(rotated).to have_been_requested.once
    expect(a_request(:post, login_url)).to have_been_made.twice
  end

  it 'removes the cached token after a second 401' do
    stub_request(:get, url).to_return(status: 401)
    expect { client.request(:get, '/api/v1/admin/dids') }.to raise_error(Pabx::Error, 'INVALID_CREDENTIALS')
    expect(Rails.cache.read(client.send(:cache_key))).to be_nil
    expect(a_request(:post, login_url)).to have_been_made.twice
    expect(a_request(:get, url)).to have_been_made.twice
  end

  it 'passes peer verification and bounded timeout options to the SSRF transport' do
    expect(SsrfFilter).to receive(:get).with(url, headers: anything, body: nil, max_redirects: 0,
                                           http_options: { open_timeout: 3, read_timeout: 15,
                                                           verify_mode: OpenSSL::SSL::VERIFY_PEER }).and_call_original
    expect(client.request(:get, '/api/v1/admin/dids')).to eq([])
  end

  it 'sanitizes a TLS verification failure without retrying it' do
    stub_request(:get, url).to_raise(OpenSSL::SSL::SSLError.new('synthetic-api-password synthetic-bearer'))
    expect { client.request(:get, '/api/v1/admin/dids') }.to raise_error(Pabx::Error, 'UNAVAILABLE') do |error|
      expect(error.full_message.match?(/synthetic-api-password|synthetic-bearer/)).to be(false)
    end
    expect(a_request(:get, url)).to have_been_made.once
  end

  it 'does not retain invalid JSON containing secrets in the exception chain' do
    stub_request(:get, url).to_return(body: 'synthetic-api-password synthetic-bearer')
    expect { client.request(:get, '/api/v1/admin/dids') }.to raise_error(Pabx::Error, 'INVALID_RESPONSE') do |error|
      expect(error.full_message.match?(/synthetic-api-password|synthetic-bearer/)).to be(false)
    end
  end

  it 'does not log credentials tokens or the provider error body' do
    integration
    output = StringIO.new
    allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(output))
    stub_request(:get, url).to_return(status: 500, body: 'synthetic-api-password synthetic-bearer')
    expect { client.request(:get, '/api/v1/admin/dids') }.to raise_error(Pabx::Error, 'PROVIDER_ERROR')
    expect(output.string.match?(/synthetic-api-password|synthetic-bearer/)).to be(false)
    expect(client.inspect.match?(/synthetic-api-password|synthetic-bearer/)).to be(false)
  end

  ['https://other.example.test/api/v1/admin/dids', '/api/v1/../secret'].each do |endpoint|
    it "rejects the untrusted endpoint #{endpoint}" do
      expect { client.request(:get, endpoint) }.to raise_error(Pabx::Error, 'INVALID_ENDPOINT')
      expect(a_request(:get, url)).not_to have_been_made
      expect(a_request(:any, /other\.example\.test/)).not_to have_been_made
    end
  end
end
