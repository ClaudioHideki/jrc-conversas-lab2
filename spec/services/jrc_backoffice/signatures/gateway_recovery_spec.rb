require 'rails_helper'

# Every provider response is WebMock simulation; no external demo was used.
RSpec.describe JrcBackoffice::Signatures::Gateway do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:configuration) { JrcBackoffice::SignatureConfiguration.new(account: account, actor: actor) }
  let(:settings) do
    { environment: 'demo', enabled: true, integration_key: SecureRandom.uuid, impersonated_user_id: SecureRandom.uuid,
      external_account_id: SecureRandom.uuid, private_key: OpenSSL::PKey::RSA.new(2048).to_pem,
      connect_hmac_keys: ['synthetic-only-recovery-hmac-key-not-external-123456'] }
  end
  let(:connection) { configuration.save!(attributes: settings, expected_revision: 0).connection }
  let(:gateway) { described_class.new(connection: connection) }
  let(:transaction_id) { SecureRandom.uuid }
  let(:external_id) { SecureRandom.uuid }
  let(:root) { "https://demo.docusign.net/restapi/v2.1/accounts/#{connection.external_account_id}" }

  before do
    account.enable_features!('jrc_crm')
    stub_request(:post, 'https://account-d.docusign.com/oauth/token')
      .to_return(status: 200, body: { access_token: 'synthetic-token-only', expires_in: 3600 }.to_json)
    stub_request(:get, 'https://account-d.docusign.com/oauth/userinfo').to_return do
      { status: 200, body: { sub: connection.impersonated_user_id,
                             accounts: [{ account_id: connection.external_account_id, base_uri: 'https://demo.docusign.net' }] }.to_json }
    end
    stub_request(:get, "#{root}/envelopes").with(query: { transaction_ids: transaction_id, count: '2' })
                                           .to_return(status: 200, body: { envelopes: [{ envelopeId: external_id }], totalSetSize: '1',
                                                                           nextUri: '' }.to_json)
    stub_request(:get, "#{root}/envelopes/#{external_id}")
      .to_return(status: 200, body: { envelopeId: external_id, transactionId: transaction_id, status: 'sent' }.to_json)
  end

  it 'finds only the persisted transaction within the pinned authenticated external account without writing' do
    expect(gateway.recover_send(transaction_id: transaction_id)).to include(found: true, external_id: external_id, state: 'waiting')
    expect(WebMock).to have_requested(:get, "#{root}/envelopes").with(query: { transaction_ids: transaction_id, count: '2' }).once
    expect(WebMock).not_to have_requested(:post, "#{root}/envelopes")
  end

  it 'treats an empty result as unknown, never permission to repeat an uncertain POST' do
    stub_request(:get, "#{root}/envelopes").with(query: { transaction_ids: transaction_id, count: '2' })
                                           .to_return(status: 200, body: { envelopes: [], totalSetSize: '0' }.to_json)
    expect(gateway.recover_send(transaction_id: transaction_id)).to eq(found: false, state: 'unknown')
    expect(WebMock).not_to have_requested(:get, "#{root}/envelopes/#{external_id}")
    expect(WebMock).not_to have_requested(:post, "#{root}/envelopes")
  end

  it 'keeps completion reported distinct from internally verified signature' do
    stub_request(:get, "#{root}/envelopes/#{external_id}")
      .to_return(status: 200, body: { envelopeId: external_id, transactionId: transaction_id, status: 'completed' }.to_json)
    expect(gateway.recover_send(transaction_id: transaction_id)).to include(found: true, state: 'completion_reported')
  end

  it 'rejects a transaction mismatch even if the lookup returned only one plausible envelope' do
    stub_request(:get, "#{root}/envelopes/#{external_id}")
      .to_return(status: 200, body: { envelopeId: external_id, transactionId: SecureRandom.uuid, status: 'sent' }.to_json)
    expect do
      gateway.recover_send(transaction_id: transaction_id)
    end.to raise_error(JrcBackoffice::Signatures::ProviderError, 'PROVIDER_RESPONSE_INVALID')
  end

  it 'rejects a missing transaction binding rather than guessing from ID or recipient email' do
    stub_request(:get, "#{root}/envelopes/#{external_id}").to_return(status: 200, body: { envelopeId: external_id, status: 'sent' }.to_json)
    expect do
      gateway.recover_send(transaction_id: transaction_id)
    end.to raise_error(JrcBackoffice::Signatures::ProviderError, 'PROVIDER_RESPONSE_INVALID')
  end

  it 'rejects multiple or incomplete pages instead of selecting the first envelope' do
    stub_request(:get, "#{root}/envelopes").with(query: { transaction_ids: transaction_id, count: '2' })
                                           .to_return(status: 200, body: {
                                             envelopes: [{ envelopeId: external_id }, { envelopeId: SecureRandom.uuid }], totalSetSize: '2'
                                           }.to_json)
    expect do
      gateway.recover_send(transaction_id: transaction_id)
    end.to raise_error(JrcBackoffice::Signatures::ProviderError, 'PROVIDER_RESPONSE_INVALID')
    expect(WebMock).not_to have_requested(:get, "#{root}/envelopes/#{external_id}")
  end

  it 'does not trust a single partial result with further pages' do
    stub_request(:get, "#{root}/envelopes").with(query: { transaction_ids: transaction_id, count: '2' })
                                           .to_return(status: 200, body: { envelopes: [{ envelopeId: external_id }], totalSetSize: '2',
                                                                           nextUri: '/next' }.to_json)
    expect do
      gateway.recover_send(transaction_id: transaction_id)
    end.to raise_error(JrcBackoffice::Signatures::ProviderError, 'PROVIDER_RESPONSE_INVALID')
  end

  it 'does not route recovery through a replacement default connection or environment' do
    pinned = connection
    configuration.save!(attributes: settings.merge(environment: 'production', external_account_id: SecureRandom.uuid), expected_revision: 1)
    expect(gateway.recover_send(transaction_id: transaction_id)).to include(found: true, external_id: external_id)
    expect(pinned.reload.environment).to eq('demo')
    expect(WebMock).not_to have_requested(:post, 'https://account.docusign.com/oauth/token')
  end

  it 'rejects malformed transaction IDs before any provider request' do
    expect { gateway.recover_send(transaction_id: '../anything') }.to raise_error(JrcBackoffice::Signatures::ProviderError, 'PROVIDER_ID_INVALID')
    expect(WebMock).not_to have_requested(:post, 'https://account-d.docusign.com/oauth/token')
  end

  it 'fails safely on a lookup timeout and never resubmits the envelope' do
    stub_request(:get, "#{root}/envelopes").with(query: { transaction_ids: transaction_id, count: '2' }).to_timeout
    expect { gateway.recover_send(transaction_id: transaction_id) }.to raise_error(JrcBackoffice::Signatures::ProviderError, 'PROVIDER_UNAVAILABLE')
    expect(WebMock).not_to have_requested(:post, "#{root}/envelopes")
  end
end
