require 'rails_helper'

# All HTTP replies are simulated. These cases validate isolation of the
# connector, not consent, delivery or signature in the real DocuSign demo.
RSpec.describe JrcBackoffice::Signatures::Gateway do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:configuration) { JrcBackoffice::SignatureConfiguration.new(account: account, actor: admin) }
  let(:secret) { 'synthetic-pinned-connection-hmac-1234567890' }
  let(:attributes) do
    { environment: 'demo', integration_key: SecureRandom.uuid, impersonated_user_id: SecureRandom.uuid,
      external_account_id: SecureRandom.uuid, enabled: true, private_key: OpenSSL::PKey::RSA.new(2048).to_pem,
      connect_hmac_keys: [secret] }
  end
  let(:integration) { configuration.save!(attributes: attributes, expected_revision: 0) }
  let(:connection) { integration.connection }
  let(:gateway) { described_class.new(connection: connection) }
  let(:external_id) { SecureRandom.uuid }
  let(:api_root) { "https://demo.docusign.net/restapi/v2.1/accounts/#{connection.external_account_id}" }
  let(:signers) { [{ id: '1', name: 'TESTE SINTÉTICO — Assinante', email: 'signer@example.test', anchor: '/jrc_sign_1/' }] }

  before do
    account.enable_features!('jrc_crm')
    stub_request(:post, 'https://account-d.docusign.com/oauth/token')
      .to_return(status: 200, body: { access_token: 'synthetic-token', expires_in: 3600 }.to_json)
    stub_request(:get, 'https://account-d.docusign.com/oauth/userinfo').to_return do
      { status: 200, body: { sub: connection.impersonated_user_id,
                             accounts: [{ account_id: connection.external_account_id, base_uri: 'https://demo.docusign.net' }] }.to_json }
    end
  end

  it 'pins encrypted provider, environment, credentials and account while a new default receives a new callback' do
    old = connection
    original = old.attributes
    configuration.save!(attributes: attributes.merge(environment: 'production', external_account_id: SecureRandom.uuid,
                                                     private_key: OpenSSL::PKey::RSA.new(2048).to_pem), expected_revision: 1)
    current = integration.reload.connection
    expect(old.reload.attributes).to eq(original)
    expect(old.credentials['private_key']).to eq(attributes[:private_key].strip)
    expect(current.public_id).not_to eq(old.public_id)
    expect(current.environment).to eq('production')
    expect(old.serializable_hash.to_s).not_to include('private_key', 'credentials', old.external_account_id)
  end

  it 'retains the provider and demo account on a historical resend after the default changes' do
    connection.update!(authorization_checked_at: Time.current, connect_checked_at: Time.current)
    old_gateway = gateway
    configuration.save!(attributes: attributes.merge(environment: 'production', external_account_id: SecureRandom.uuid), expected_revision: 1)
    stub_request(:put, "#{api_root}/envelopes/#{external_id}?resend_envelope=true").to_return(status: 200, body: '{}')
    expect(old_gateway.resend(external_id)).to be(true)
    expect(WebMock).to have_requested(:put, "#{api_root}/envelopes/#{external_id}?resend_envelope=true").once
    expect(WebMock).not_to have_requested(:post, 'https://account.docusign.com/oauth/token')
  end

  it 'does not route a historical resend through a replacement default provider' do
    connection.update!(authorization_checked_at: Time.current, connect_checked_at: Time.current)
    old_gateway = gateway
    ActiveRecord::Base.connection.execute("UPDATE jrc_backoffice_signature_integrations SET provider='not-installed' WHERE id=#{integration.id}")
    stub_request(:put, "#{api_root}/envelopes/#{external_id}?resend_envelope=true").to_return(status: 200, body: '{}')
    expect(old_gateway.resend(external_id)).to be(true)
    expect(connection.reload.provider).to eq('docusign')
    expect(connection.current_for_new_delivery?).to be(false)
  end

  it 'reloads the pinned configuration rather than trusting unsaved edits on the record instance' do
    connection.environment = 'production'
    stub_request(:get, "#{api_root}/envelopes/#{external_id}")
      .to_return(status: 200, body: { envelopeId: external_id, status: 'sent' }.to_json)
    expect(gateway.status(external_id)).to include(state: 'waiting')
    expect(connection.environment).to eq('demo')
    expect(WebMock).not_to have_requested(:post, 'https://account.docusign.com/oauth/token')
  end

  it 'selects the new default only for a new admission and never falls back to the verified old connection' do
    connection.update!(authorization_checked_at: Time.current, connect_checked_at: Time.current)
    selected = JrcBackoffice::Signatures::ConnectionSelection.for_new_delivery(account: account)
    configuration.save!(attributes: attributes, expected_revision: 1)
    expect do
      JrcBackoffice::Signatures::ConnectionSelection.for_new_delivery(account: account)
    end.to raise_error(JrcBackoffice::Signatures::ProviderError, 'CONNECTION_NOT_READY')
    expect(selected.id).to eq(connection.id)
    expect(WebMock).not_to have_requested(:post, /envelopes/)
  end

  it 'uses the admitted connection for submission even if the default changes while work is queued' do
    connection.update!(authorization_checked_at: Time.current, connect_checked_at: Time.current)
    selected = JrcBackoffice::Signatures::ConnectionSelection.for_new_delivery(account: account)
    configuration.save!(attributes: attributes.merge(environment: 'production'), expected_revision: 1)
    stub_request(:post, "#{api_root}/envelopes").to_return(status: 201, body: { envelopeId: external_id, status: 'sent' }.to_json)
    admitted = described_class.new(connection: selected)
    result = admitted.send_for_signature(document: '%PDF-synthetic', signers: signers, subject: 'TESTE SINTÉTICO', transaction_id: SecureRandom.uuid)
    expect(result).to include(state: 'sent', external_id: external_id)
    expect(WebMock).not_to have_requested(:post, 'https://account.docusign.com/oauth/token')
  end

  it 'translates the internal document and signer fields only inside the connector' do
    connection.update!(authorization_checked_at: Time.current, connect_checked_at: Time.current)
    transaction = SecureRandom.uuid
    stub_request(:post, "#{api_root}/envelopes").with do |request|
      data = JSON.parse(request.body)
      expect(data).to include('status' => 'sent', 'transactionId' => transaction)
      expect(Base64.decode64(data.fetch('documents').first.fetch('documentBase64'))).to eq('%PDF-synthetic')
      expect(data.dig('recipients', 'signers', 0, 'tabs', 'signHereTabs', 0, 'anchorIgnoreIfNotPresent')).to eq('false')
    end.to_return(status: 201, body: { envelopeId: external_id, status: 'sent' }.to_json)
    expect(gateway.send_for_signature(document: '%PDF-synthetic', signers: signers, subject: 'TESTE SINTÉTICO', transaction_id: transaction))
      .to include(external_id: external_id, state: 'sent')
  end

  it 'does not promote a reported provider completion to a verified signed contract' do
    stub_request(:get, "#{api_root}/envelopes/#{external_id}")
      .to_return(status: 200, body: { envelopeId: external_id, status: 'completed' }.to_json)
    expect { expect(gateway.status(external_id)).to include(state: 'completion_reported') }.not_to change(JrcCrm::Contract, :count)
  end

  it 'retains an uncertain send error without resubmitting a document' do
    connection.update!(authorization_checked_at: Time.current, connect_checked_at: Time.current)
    stub_request(:post, "#{api_root}/envelopes").to_timeout
    expect do
      gateway.send_for_signature(document: '%PDF-synthetic', signers: signers, subject: 'TESTE SINTÉTICO', transaction_id: SecureRandom.uuid)
    end.to raise_error(JrcBackoffice::Signatures::ProviderError) { |error| expect(error.uncertain?).to be(true) }
    expect(WebMock).to have_requested(:post, "#{api_root}/envelopes").once
  end

  it 'uses provider cancellation and evidence capabilities through the internal boundary' do
    stub_request(:put, "#{api_root}/envelopes/#{external_id}").with(body: { status: 'voided', voidedReason: 'TESTE SINTÉTICO' }.to_json)
                                                              .to_return(status: 200, body: '{}')
    stub_request(:get, "#{api_root}/envelopes/#{external_id}/documents/certificate")
      .to_return(status: 200, body: '%PDF-synthetic-certificate', headers: { 'Content-Type' => 'application/pdf' })
    expect(gateway.capabilities).to include(:cancel, :certificate, :remind)
    expect(gateway.cancel(external_id, reason: 'TESTE SINTÉTICO')).to be(true)
    expect(gateway.document(external_id, kind: :certificate)).to eq('%PDF-synthetic-certificate')
  end

  it 'does not reinterpret unknown provider states as successful completion' do
    stub_request(:get, "#{api_root}/envelopes/#{external_id}")
      .to_return(status: 200, body: { envelopeId: external_id, status: 'unrecognized-future-state' }.to_json)
    expect(gateway.status(external_id)).to include(state: 'unknown')
  end

  it 'refuses an uninstalled provider instead of silently routing it to the default' do
    allow(connection).to receive(:provider).and_return('not-installed')
    expect { described_class.new(connection: connection) }.to raise_error(JrcBackoffice::Signatures::ProviderError, 'PROVIDER_UNAVAILABLE')
    expect(WebMock).not_to have_requested(:any, /oauth/)
  end

  it 'prevents rewriting pinned connection fields in the database' do
    id = connection.id
    expect do
      JrcBackoffice::SignatureConnection.transaction(requires_new: true) do
        ActiveRecord::Base.connection.execute("UPDATE jrc_backoffice_signature_connections SET environment='production' WHERE id=#{id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /snapshots are immutable/)
    expect(connection.reload.environment).to eq('demo')
    expect do
      JrcBackoffice::SignatureConnection.transaction(requires_new: true) do
        ActiveRecord::Base.connection.execute("DELETE FROM jrc_backoffice_signature_connections WHERE id=#{id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /snapshots are immutable/)
    expect(JrcBackoffice::SignatureConnection.where(id: id)).to exist
  end

  it 'enforces the account and integration pair when insertion bypasses model validation' do
    record = connection
    foreign = create(:account)
    database = ActiveRecord::Base.connection
    fields = JrcBackoffice::SignatureConnection::CONFIGURATION + ['updated_at']
    replacements = { 'account_id' => foreign.id.to_s, 'public_id' => database.quote(SecureRandom.uuid), 'revision' => (record.revision + 1).to_s }
    columns = fields.map { |field| database.quote_column_name(field) }.join(',')
    values = fields.map { |field| replacements.fetch(field) { database.quote_column_name(field) } }.join(',')
    expect do
      JrcBackoffice::SignatureConnection.transaction(requires_new: true) do
        database.execute("INSERT INTO jrc_backoffice_signature_connections (#{columns}) SELECT #{values} " \
                         "FROM jrc_backoffice_signature_connections WHERE id=#{record.id}")
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(JrcBackoffice::SignatureConnection.where(account_id: foreign.id)).not_to exist
  end

  it 'refuses historical provider calls after the account CRM feature is revoked' do
    old_gateway = gateway
    account.disable_features!('jrc_crm')
    expect { old_gateway.resend(external_id) }.to raise_error(JrcBackoffice::Signatures::ProviderError, 'CONNECTION_NOT_READY')
    expect(WebMock).not_to have_requested(:any, /oauth/)
  end
end
