require 'rails_helper'

RSpec.describe Pabx::Client, :pabx do
  let(:integration) { create(:telephony_integration, pabx_settings: pabx_settings, pabx_username: 'synthetic@example.test', pabx_password: 'synthetic-api-password') }
  let(:client) { described_class.new(integration) }
  let(:url) { 'https://pbx.example.test/api/v1/admin/dids' }
  let(:login_url) { 'https://pbx.example.test/api/v1/auth/login' }
  before do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(Resolv).to receive(:getaddresses).with('pbx.example.test').and_return(['93.184.216.34'])
    stub_request(:post, login_url).with(body: { email: 'synthetic@example.test', password: 'synthetic-api-password' }.to_json)
      .to_return(body: { token: 'synthetic-bearer' }.to_json)
  end

  it 'authenticates automatically, reuses an encrypted temporary token and sends Bearer only to the configured API' do
    stub_request(:get, url).with(headers: { 'Authorization' => 'Bearer synthetic-bearer' }).to_return(body: '[]')
    2.times { expect(client.request(:get, '/api/v1/admin/dids')).to eq([]) }
    expect(a_request(:post, login_url)).to have_been_made.once
    encrypted = Rails.cache.read(client.send(:cache_key))
    expect(encrypted).not_to include('synthetic-bearer')
    expect(client.inspect).not_to include('synthetic-api-password')
  end

  it 'renews once after a 401 and retries the original request once' do
    stub_request(:get, url).to_return(status: 401).then.to_return(body: '[]')
    expect(client.request(:get, '/api/v1/admin/dids')).to eq([])
    expect(a_request(:post, login_url)).to have_been_made.twice
    expect(a_request(:get, url)).to have_been_made.twice
  end

  it 'stops after the second 401 without leaking request or response secrets' do
    stub_request(:get, url).to_return(status: 401, body: 'secret vendor response')
    expect { client.request(:get, '/api/v1/admin/dids') }.to raise_error(Pabx::Error, 'INVALID_CREDENTIALS')
    expect(a_request(:post, login_url)).to have_been_made.twice
    expect(a_request(:get, url)).to have_been_made.twice
  end

  [403, 404, 422, 429, 500, 503].each do |status|
    it "sanitizes HTTP #{status} and does not retry it" do
      stub_request(:get, url).to_return(status: status, body: 'password=private auth=Bearer raw')
      expect { client.request(:get, '/api/v1/admin/dids') }.to raise_error(Pabx::Error) { |e| expect(e.message).not_to match(/private|Bearer|password/) }
      expect(a_request(:get, url)).to have_been_made.once
    end
  end

  it 'rejects invalid login credentials without retrying login' do
    stub_request(:post, login_url).to_return(status: 401)
    expect { client.request(:get, '/api/v1/admin/dids') }.to raise_error(Pabx::Error, 'INVALID_CREDENTIALS')
    expect(a_request(:post, login_url)).to have_been_made.once
  end

  ['not-json', 'null', '123', '{"unexpected":true}'].each do |body|
    it "rejects an unsupported token response #{body}" do
      stub_request(:post, login_url).to_return(body: body)
      expect { client.request(:get, '/api/v1/admin/dids') }.to raise_error(Pabx::Error)
    end
  end

  it 'sanitizes invalid JSON after authentication' do
    stub_request(:get, url).to_return(body: '<html>private body</html>')
    expect { client.request(:get, '/api/v1/admin/dids') }.to raise_error(Pabx::Error, 'INVALID_RESPONSE')
  end

  it 'bounds response size' do
    stub_request(:get, url).to_return(body: 'x' * (described_class::MAX_JSON_BYTES + 1))
    expect { client.request(:get, '/api/v1/admin/dids') }.to raise_error(Pabx::Error, 'RESPONSE_TOO_LARGE')
  end

  it 'handles timeouts without exposing the URL or credentials' do
    stub_request(:get, url).to_timeout
    expect { client.request(:get, '/api/v1/admin/dids') }.to raise_error(Pabx::Error, 'TIMEOUT')
  end

  it 'handles connection refusal' do
    stub_request(:get, url).to_raise(Errno::ECONNREFUSED)
    expect { client.request(:get, '/api/v1/admin/dids') }.to raise_error(Pabx::Error, 'UNAVAILABLE')
  end

  it 'blocks redirects instead of forwarding the login body or Bearer' do
    stub_request(:post, login_url).to_return(status: 302, headers: { Location: 'https://other.example.test/collect' })
    expect { client.request(:get, '/api/v1/admin/dids') }.to raise_error(Pabx::Error, 'UNSAFE_ORIGIN')
    expect(a_request(:any, /other\.example\.test/)).not_to have_been_made
  end

  it 'blocks private DNS and metadata addresses even when the shared SafeFetch private-network switch is enabled' do
    allow(Resolv).to receive(:getaddresses).with('pbx.example.test').and_return(['169.254.169.254'])
    with_modified_env SAFE_FETCH_ALLOW_PRIVATE_NETWORK: 'true' do
      expect { client.request(:get, '/api/v1/admin/dids') }.to raise_error(Pabx::Error, 'UNSAFE_ORIGIN')
    end
    expect(a_request(:post, login_url)).not_to have_been_made
  end

  it 'does not reuse a token across Accounts or changed credentials' do
    stub_request(:get, url).to_return(body: '[]')
    client.request(:get, '/api/v1/admin/dids')
    other = create(:telephony_integration, pabx_settings: pabx_settings, pabx_username: 'synthetic@example.test', pabx_password: 'synthetic-api-password')
    described_class.new(other).request(:get, '/api/v1/admin/dids')
    expect(a_request(:post, login_url)).to have_been_made.twice
  end
end
