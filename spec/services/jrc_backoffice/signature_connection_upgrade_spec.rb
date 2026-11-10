require 'rails_helper'
require Rails.root.join('db/migrate/20261102040000_pin_signature_provider_connections')
require Rails.root.join('db/migrate/20261102090100_create_backoffice_signature_deliveries')

RSpec.describe JrcBackoffice::SignatureConnection, :unused_signature_upgrade do
  it 'backfills the existing connection and known notification revision without changing native data or old ciphertext' do
    raise 'Disposable database required' unless Rails.env.test? && ENV['POSTGRES_DATABASE'] == 'jrc_rel_v2_candidate_test'

    account = create(:account)
    admin = create(:user, account: account, role: :administrator)
    conversation = create(:conversation, account: account)
    account.enable_features!('jrc_crm')
    credentials = { private_key: OpenSSL::PKey::RSA.new(2048).to_pem, connect_hmac_keys: ['synthetic-upgrade-only-connect-key-123456'] }
    configuration = credentials.merge(environment: 'demo', enabled: true, integration_key: SecureRandom.uuid,
                                      impersonated_user_id: SecureRandom.uuid, external_account_id: SecureRandom.uuid)
    integration = JrcBackoffice::SignatureConfiguration.new(account: account, actor: admin).save!(attributes: configuration, expected_revision: 0)
    payload = { event: 'envelope-sent', generatedDateTime: Time.current.iso8601,
                data: { accountId: integration.external_account_id, envelopeId: SecureRandom.uuid } }.to_json
    signature = Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', credentials[:connect_hmac_keys].first, payload))
    notification = JrcBackoffice::Docusign::ConnectInbox.receive!(public_id: integration.connection.public_id,
                                                                  raw_body: payload, signatures: [signature])
    ciphertext = integration.encrypted_credentials
    native = conversation.reload.attributes
    counts = [Account.count, Contact.count, Conversation.count, Message.count]
    with_unused_signature_evidence do
      CreateBackofficeSignatureDeliveries.new.migrate(:down)
      PinSignatureProviderConnections.new.migrate(:down)
      PinSignatureProviderConnections.new.migrate(:up)
      CreateBackofficeSignatureDeliveries.new.migrate(:up)
      [described_class, JrcBackoffice::SignatureIntegration, JrcBackoffice::SignatureNotification].each(&:reset_column_information)
      connection = integration.reload.connection
      expect(connection).to have_attributes(provider: 'docusign', public_id: integration.public_id)
      expect(connection.encrypted_credentials).to eq(ciphertext)
      expect(connection.credentials['private_key']).to eq(credentials[:private_key].strip)
      expect(notification.reload.connection_id).to eq(connection.id)
      expect(notification.payload).to eq(JSON.parse(payload))
      expect([Account.count, Contact.count, Conversation.count, Message.count]).to eq(counts)
      expect(conversation.reload.attributes).to eq(native)
    end
  ensure
    ActiveRecord::Base.connection.schema_cache.clear!
    [described_class, JrcBackoffice::SignatureIntegration, JrcBackoffice::SignatureNotification].each(&:reset_column_information)
  end
end
