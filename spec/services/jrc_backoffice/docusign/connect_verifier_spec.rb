require 'rails_helper'

RSpec.describe JrcBackoffice::Docusign::ConnectVerifier do
  let(:key) { 'synthetic-connect-key-for-tests-only-1234' }
  let(:body) { '{"event":"envelope-completed","data":{"accountId":"synthetic"}}' }
  let(:signature) { Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', key, body)) }

  it 'verifies the exact raw bytes with the configured secret' do
    expect(described_class.valid?(raw_body: body, signatures: [signature], keys: [key])).to be(true)
  end

  it 'refuses a tampered or reserialized body' do
    expect(described_class.valid?(raw_body: "#{body} ", signatures: [signature], keys: [key])).to be(false)
  end

  it 'does not accept the key or signature of a different internal account' do
    expect(described_class.valid?(raw_body: body, signatures: [signature], keys: ['other-account-synthetic-secret-12345678'])).to be(false)
  end

  it 'supports bounded key rotation while still requiring a valid signature' do
    expect(described_class.valid?(raw_body: body, signatures: ['invalid', signature],
                                  keys: ['old-synthetic-key-not-valid-anymore-1234', key])).to be(true)
  end

  it 'refuses missing configuration and an oversized notification' do
    expect(described_class.valid?(raw_body: body, signatures: [], keys: [])).to be(false)
    expect(described_class.valid?(raw_body: 'x' * (2.megabytes + 1), signatures: [signature], keys: [key])).to be(false)
  end
end
