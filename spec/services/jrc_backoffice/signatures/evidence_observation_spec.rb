require 'rails_helper'

# Real immutable legal admissions and permissions. Gateway replies/PDF bytes are
# synthetic and do not demonstrate provider or cryptographic PDF acceptance.
RSpec.describe JrcBackoffice::Signatures::EvidenceObservation, :approval_core, :authority_core, :signature_delivery_core do
  let(:domain) { admitted_signature_domain }
  let(:delivery) { domain.fetch(:delivery) }
  let(:external_id) { SecureRandom.uuid }
  let(:gateway) { instance_double(JrcBackoffice::Signatures::Gateway) }
  let(:provider_data) do
    { external_id: external_id, state: 'completion_reported', document_references: ['1'], observed_at: Time.current.iso8601(6),
      signers: delivery.snapshot.fetch('recipients').map do |row|
        { id: row.fetch('position').to_s, name: row.fetch('name'), email: row.fetch('email'), completed: true,
          signed_at: Time.current.iso8601(6), provider_state: 'completed' }
      end,
      signed_document: "%PDF-1.4\nSYNTHETIC SIGNED CONTENT ONLY", certificate: "%PDF-1.4\nSYNTHETIC CERTIFICATE ONLY" }
  end
  let(:observation) { described_class.new(delivery: delivery, actor: domain.fetch(:actor)) }

  before do
    raise 'Owned synthetic evidence database required' unless Rails.env.test? && ENV['POSTGRES_DATABASE'] == 'jrc_rel_v2_candidate_test'

    delivery.events.create!(account: delivery.account, connection: delivery.connection, kind: 'send_confirmed', event_key: 'synthetic-ack',
                            external_id: external_id, source_snapshot: '{}')
    allow(JrcBackoffice::Signatures::Gateway).to receive(:new).with(connection: delivery.connection).and_return(gateway)
    allow(gateway).to receive(:evidence).with(external_id).and_return(provider_data)
  end

  it 'binds both actual returned byte hashes to the exact admission/version without releasing or signing a contract' do
    before = [domain[:contract].attributes, delivery.attributes, delivery.events.count]
    result = observation.call
    expected = { 'delivery_id' => delivery.id, 'contract_version_id' => delivery.contract_version_id, 'connection_id' => delivery.connection_id,
                 'external_id' => external_id, 'pdf_sha256' => delivery.contract_version.pdf_sha256 }
    expect(result.fetch(:binding)).to include(expected)
    expect(result.fetch(:artifacts).fetch(:signed_document).fetch(:sha256)).to eq(Digest::SHA256.hexdigest(provider_data[:signed_document]))
    expect(result.fetch(:artifacts).fetch(:certificate).fetch(:sha256)).to eq(Digest::SHA256.hexdigest(provider_data[:certificate]))
    expect(result.fetch(:signers).pluck('key')).to eq(delivery.snapshot.fetch('recipients').pluck('key'))
    expect([domain[:contract].reload.attributes, delivery.reload.attributes, delivery.events.count]).to eq(before)
    expect(JrcApprovals::SignatureEvidence.call(domain[:contract]).fetch('state')).to eq('pending_provider')
  end

  it 'rejects another envelope and an unfinished signer rather than trusting the reported completed state' do
    provider_data[:external_id] = SecureRandom.uuid
    expect { observation.call }.to raise_error(JrcBackoffice::Signatures::DeliveryError, 'PROVIDER_EVIDENCE_BINDING_INVALID')
    provider_data[:external_id] = external_id
    provider_data[:signers][0][:completed] = false
    expect { observation.call }.to raise_error(JrcBackoffice::Signatures::DeliveryError, 'SIGNATURE_RECIPIENT_MISMATCH')
  end

  it 'requires the original recipient identity and refuses duplicate recipient positions' do
    provider_data[:signers][0][:email] = 'another-person@example.test'
    expect { observation.call }.to raise_error(JrcBackoffice::Signatures::DeliveryError, 'SIGNATURE_RECIPIENT_MISMATCH')
    provider_data[:signers][0][:email] = delivery.snapshot.fetch('recipients')[0].fetch('email')
    provider_data[:signers][1][:id] = provider_data[:signers][0][:id]
    expect { observation.call }.to raise_error(JrcBackoffice::Signatures::DeliveryError, 'SIGNATURE_RECIPIENT_MISMATCH')
  end

  it 'does not accept missing/invalid PDF bytes as a signed file or certificate' do
    provider_data[:certificate] = nil
    expect { observation.call }.to raise_error(JrcBackoffice::Signatures::DeliveryError, 'SIGNATURE_FILE_INVALID')
    provider_data[:certificate] = '%PDF-1.4 synthetic certificate'
    provider_data[:signed_document] = 'not-a-PDF'
    expect { observation.call }.to raise_error(JrcBackoffice::Signatures::DeliveryError, 'SIGNATURE_FILE_INVALID')
  end

  it 'rejects signatures outside the exact frozen authority validity period' do
    travel_to(45.days.from_now) do
      provider_data[:signers].each { |row| row[:signed_at] = Time.current.iso8601(6) }
      provider_data[:observed_at] = Time.current.iso8601(6)
      expect { observation.call }.to raise_error(JrcBackoffice::Signatures::DeliveryError, 'SIGNATURE_AUTHORITY_OUTSIDE_VALIDITY')
    end
  end

  it 'denies a foreign account actor before reading provider bytes' do
    actor = create(:user, account: create(:account), role: :administrator)
    expect(gateway).not_to receive(:evidence)
    expect { described_class.new(delivery: delivery, actor: actor).call }.to raise_error(Pundit::NotAuthorizedError)
  end
end
