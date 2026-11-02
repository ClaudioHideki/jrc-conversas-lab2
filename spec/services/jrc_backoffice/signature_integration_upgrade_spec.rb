require 'rails_helper'
require Rails.root.join('db/migrate/20261102010000_create_backoffice_signature_integrations')
require Rails.root.join('db/migrate/20261102020000_create_backoffice_signature_notifications')
require Rails.root.join('db/migrate/20261102040000_pin_signature_provider_connections')

RSpec.describe JrcBackoffice::SignatureIntegration do
  it 'reverses and reapplies the isolated signature tables while preserving native account and conversation data' do
    raise 'Disposable database required' unless Rails.env.test? && ENV['POSTGRES_DATABASE'] == 'jrc_rel_v2_candidate_test'

    connection = ActiveRecord::Base.connection
    account = create(:account)
    conversation = create(:conversation, account: account)
    original = conversation.reload.attributes
    counts = [Account.count, Contact.count, Conversation.count, Message.count]
    expect([JrcBackoffice::SignatureNotification.count, described_class.count]).to eq([0, 0])
    PinSignatureProviderConnections.new.migrate(:down)
    CreateBackofficeSignatureNotifications.new.migrate(:down)
    CreateBackofficeSignatureIntegrations.new.migrate(:down)
    expect(connection.table_exists?(:jrc_backoffice_signature_integrations)).to be(false)
    CreateBackofficeSignatureIntegrations.new.migrate(:up)
    CreateBackofficeSignatureNotifications.new.migrate(:up)
    PinSignatureProviderConnections.new.migrate(:up)
    expect([Account.count, Contact.count, Conversation.count, Message.count]).to eq(counts)
    expect(conversation.reload.attributes).to eq(original)
    expect(connection.index_exists?(:jrc_backoffice_signature_integrations, :account_id, unique: true)).to be(true)
    columns = %i[integration_id integration_revision body_sha256]
    expect(connection.index_exists?(:jrc_backoffice_signature_notifications, columns, unique: true)).to be(true)
    reference = connection.foreign_key_exists?(:jrc_backoffice_signature_notifications, :jrc_backoffice_signature_integrations,
                                               column: :integration_id)
    expect(reference).to be(true)
  ensure
    ActiveRecord::Base.connection.schema_cache.clear!
    [JrcBackoffice::SignatureIntegration, JrcBackoffice::SignatureNotification, JrcBackoffice::SignatureConnection].each(&:reset_column_information)
  end
end
