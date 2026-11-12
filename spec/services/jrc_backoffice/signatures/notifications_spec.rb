require 'rails_helper'

# Real inbox HMAC, encrypted receipts, legal admissions and native DB locks.
# Synthetic provider events only; no DocuSign demo or real signatures.
RSpec.describe JrcBackoffice::Signatures::Notifications, :approval_core, :authority_core, :signature_delivery_core do
  let(:domain) { admitted_signature_domain }
  let(:delivery) { domain.fetch(:delivery) }
  let(:connection) { domain.fetch(:connection) }
  let(:external_id) { SecureRandom.uuid }
  let(:receipt_for) do
    lambda do |event, at = Time.current, id = external_id, source = connection|
      body = { event: event, generatedDateTime: at.iso8601(6), data: { accountId: source.external_account_id, envelopeId: id } }.to_json
      signature = Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', source.credentials.fetch('connect_hmac_keys').first, body))
      JrcBackoffice::Docusign::ConnectInbox.receive!(public_id: source.public_id, raw_body: body, signatures: [signature])
    end
  end
  let(:bind) do
    lambda do
      delivery.events.create!(account: delivery.account, connection: connection, kind: 'send_confirmed', event_key: 'synthetic-ack',
                              external_id: external_id, source_snapshot: '{}')
    end
  end

  before do
    raise 'Owned notification test database required' unless Rails.env.test? && ENV['POSTGRES_DATABASE'] == 'jrc_four_domains_schema_admission_test'

    domain
  end

  it 'holds a verified receipt until exact binding exists, then records reported completion without claiming a valid signature' do
    receipt = receipt_for.call('envelope-completed')
    expect(described_class.new(receipt_id: receipt.id).call).to eq(:unbound)
    expect([receipt.reload.state, delivery.events.count]).to eq(['received', 1])
    bind.call
    domain[:account].jrc_crm_user_business_units.where(user: domain[:actor]).each { |row| row.update!(active: false) }
    expect([described_class.new(receipt_id: receipt.id).call, delivery.reload.state]).to eq([:processed, 'completion_reported'])
    expect([domain[:contract].reload.signature_status, JrcBackoffice::SignatureRelease.satisfied?(domain[:operation])]).to eq(['not_started', false])
    expect(described_class.new(receipt_id: receipt.id).call).to eq(:finished)
    expect(delivery.events.where(kind: 'completion_reported').count).to eq(1)
    expect(WebMock).not_to have_requested(:any, /docusign/)
  end

  it 'keeps historical receipts on their original connection and never binds an envelope by the replacement default' do
    bind.call
    replacement = synthetic_delivery_connection(domain[:account])
    foreign_receipt = receipt_for.call('envelope-completed', Time.current, external_id, replacement)
    expect(described_class.new(receipt_id: foreign_receipt.id).call).to eq(:unbound)
    expect(delivery.reload.state).to eq('sent')
    original_receipt = receipt_for.call('envelope-voided')
    expect(described_class.new(receipt_id: original_receipt.id).call).to eq(:processed)
    expect(delivery.reload.state).to eq('canceled')
    expect(delivery.connection_id).to eq(connection.id)
    expect(replacement.id).not_to eq(connection.id)
  end

  it 'does not infer envelope completion from a recipient and prevents older or terminal-conflicting facts from reopening a delivery' do
    bind.call
    recipient = receipt_for.call('recipient-completed')
    expect(described_class.new(receipt_id: recipient.id).call).to eq(:ignored)
    expect(delivery.reload.state).to eq('sent')
    at = Time.current
    completed = receipt_for.call('envelope-completed', at)
    expect(described_class.new(receipt_id: completed.id).call).to eq(:processed)
    older = receipt_for.call('envelope-declined', at - 1.minute)
    expect([described_class.new(receipt_id: older.id).call, delivery.reload.state]).to eq([:ignored, 'completion_reported'])
    declined = receipt_for.call('envelope-declined', at + 1.minute)
    expect(described_class.new(receipt_id: declined.id).call).to eq(:processed)
    late = receipt_for.call('envelope-completed', at + 2.minutes)
    expect(described_class.new(receipt_id: late.id).call).to eq(:ignored)
    expect([delivery.reload.state, domain[:contract].reload.signature_status]).to eq(%w[declined not_started])
  end

  it 'leaves an envelope from another account unbound even if its external identifier happens to match' do
    bind.call
    other = create(:account)
    other.enable_features!('jrc_crm')
    stranger = synthetic_delivery_connection(other)
    receipt = receipt_for.call('envelope-completed', Time.current, external_id, stranger)
    expect(described_class.new(receipt_id: receipt.id).call).to eq(:unbound)
    expect(receipt.reload.state).to eq('received')
    expect(delivery.reload.state).to eq('sent')
    expect(delivery.events.count).to eq(2)
  end
end
