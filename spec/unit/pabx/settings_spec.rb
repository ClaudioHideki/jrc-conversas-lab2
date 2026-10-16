require_relative 'unit_helper'

RSpec.describe Pabx::Settings do
  include_context 'PABX configuration unit'
  subject(:settings) { described_class.new(integration) }

  it 'keeps integration and synchronization OFF unless explicitly enabled' do
    expect(settings.enabled?).to be(false)
    expect(settings.sync_enabled?).to be(false)
    expect { settings.validate! }.not_to raise_error
  end

  [nil, [], 'configuration', { 'password' => 'not-a-setting' }].each do |value|
    it "rejects invalid settings shape #{value.class}" do
      allow(integration).to receive(:pabx_settings).and_return(value)
      expect { settings.validate! }.to raise_error(Pabx::Error, 'INVALID_SETTINGS')
    end
  end

  ['http://pbx.example.test', 'ftp://pbx.example.test', 'file:///etc/passwd',
   'https://user:password@pbx.example.test', 'https://pbx.example.test/path',
   'https://pbx.example.test?token=private', 'https://pbx.example.test#private', 'invalid url'].each_with_index do |url, index|
    it "rejects unsafe origin case #{index}" do
      configuration['base_url'] = url
      expect { settings.validate! }.to raise_error(Pabx::Error, 'INVALID_ORIGIN')
    end
  end

  it 'requires an explicit LAB switch for HTTP and reports it in the public metadata' do
    configuration.merge!('base_url' => 'http://pbx.example.test', 'allow_http_lab' => true)
    expect { settings.validate! }.not_to raise_error
    expect(settings.public_payload[:insecure_http]).to be(true)
  end

  it 'does not activate an incomplete integration' do
    configuration['enabled'] = true
    allow(integration).to receive(:pabx_password).and_return(nil)
    expect { settings.validate! }.to raise_error(Pabx::Error, 'CONFIGURATION_MISSING')
  end

  it 'rejects a string masquerading as an enable switch' do
    configuration['enabled'] = 'true'
    expect { settings.validate! }.to raise_error(Pabx::Error, 'INVALID_BOOLEAN')
  end

  [0, 31, '15'].each do |timeout|
    it "rejects an invalid timeout #{timeout.inspect}" do
      configuration['timeout_seconds'] = timeout
      expect { settings.validate! }.to raise_error(Pabx::Error, 'INVALID_LIMIT')
    end
  end

  it 'does not expose API credentials or a token in public configuration' do
    body = settings.public_payload.to_json
    expect(body).not_to include('synthetic@example.test', 'synthetic-api-password', 'fingerprint')
    expect(settings.public_payload).to include(configured: true, username_configured: true, password_configured: true)
  end

  it 'isolates cached configuration fingerprints after a credential change' do
    initial = settings.fingerprint
    allow(integration).to receive(:pabx_password).and_return('new-synthetic-password')
    expect(settings.fingerprint).not_to eq(initial)
  end
end
