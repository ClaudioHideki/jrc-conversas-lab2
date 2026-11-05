require 'rails_helper'

# Native persisted admissions/files/permissions. Provider replies and clean AV
# observations below are synthetic, not external signing/scanner homologation.
RSpec.describe JrcBackoffice::Signatures::EvidenceAcceptance, :approval_core, :authority_core, :signature_delivery_core do
  self.use_transactional_tests = false
  let(:domain) { admitted_signature_domain }
  let(:delivery) { domain.fetch(:delivery) }
  let(:external_id) { SecureRandom.uuid }
  let(:gateway) { instance_double(JrcBackoffice::Signatures::Gateway) }
  let(:payload) do
    { external_id: external_id, state: 'completion_reported', document_references: ['1'], observed_at: Time.current.iso8601(6),
      signers: delivery.snapshot.fetch('recipients').map do |row|
        { id: row.fetch('position').to_s, name: row.fetch('name'), email: row.fetch('email'), completed: true,
          signed_at: Time.current.iso8601(6), provider_state: 'completed' }
      end,
      signed_document: "%PDF-1.4\nSYNTHETIC SIGNED FILE ONLY", certificate: "%PDF-1.4\nSYNTHETIC CERTIFICATE ONLY" }
  end
  let(:bundle) do
    JrcBackoffice::Signatures::Artifacts.new(account: domain[:account], actor: domain[:actor], request_id: domain[:operation].id)
                                        .capture!(delivery_id: delivery.id)
  end
  let(:service) { described_class.new(account: domain[:account], actor: domain[:actor], request_id: domain[:operation].id) }

  before do
    config = ActiveRecord::Base.connection_db_config
    unless Rails.env.test? && config.database == 'jrc_rel_v2_candidate_test' && config.host == 'jrc-rel-v2-pg-20261101'
      raise 'Use only the owned isolated evidence candidate database'
    end

    delivery.events.create!(account: delivery.account, connection: delivery.connection, kind: 'send_confirmed', event_key: 'synthetic-ack',
                            external_id: external_id, source_snapshot: '{}')
    allow(JrcBackoffice::Signatures::Gateway).to receive(:new).with(connection: delivery.connection).and_return(gateway)
    allow(gateway).to receive(:evidence).with(external_id).and_return(payload)
  end

  def scan_bundle(state: 'clean')
    [bundle.signed_document, bundle.certificate_document].each do |version|
      JrcBackoffice::DocumentScan.create!(account: domain[:account], document_version: version, source_blob: version.file.blob,
                                          attempt: 1, state: state, expected_sha256: version.sha256,
                                          observed_sha256: version.sha256, scanner_adapter: 'clamav-instream-v1')
    end
  end

  # A single persisted lifecycle proves atomic acceptance and SQL/Ruby protections without duplicating expensive legal fixtures.
  # rubocop:disable RSpec/MultipleExpectations
  it 'requires security admission and explicit acceptance, without automatic activation or Backoffice advancement' do
    original_stage = domain[:operation].stage
    original_snapshot = bundle.snapshot.deep_dup
    expect { service.call(delivery_id: delivery.id, expected_source_digest: bundle.source_digest) }
      .to raise_error(JrcBackoffice::Signatures::DeliveryError, 'SIGNATURE_ARTIFACT_SECURITY_PENDING')
    scan_bundle
    service.call(delivery_id: delivery.id, expected_source_digest: bundle.source_digest)
    expect(domain[:contract].reload).to have_attributes(signature_status: 'signed', signature_mode: 'provider', status: 'awaiting_signature')
    expect(JrcBackoffice::SignatureRelease.verified?(domain[:contract])).to be(true)
    export = JrcBackoffice::CompletionSignature.new(account: domain[:account], actor: domain[:actor], request_id: domain[:operation].id)
    expect(export.call(domain[:contract])).to include(artifact_available: true, contract_version_id: bundle.contract_version_id,
      signed_document_version_id: bundle.signed_document_id, certificate_document_version_id: bundle.certificate_document_id)
    expect(domain[:operation].reload.stage).to eq(original_stage)
    expect(bundle.reload.snapshot).to eq(original_snapshot)
    service.call(delivery_id: delivery.id, expected_source_digest: bundle.source_digest)
    expect(JrcCrm::AuditEvent.where(account: domain[:account], event_type: 'backoffice_signature_evidence_accepted').count).to eq(1)
    expect(domain[:contract].signed_document.blob.id).to eq(bundle.signed_document.file.blob.id)
    receipt = JrcBackoffice::SignatureAcceptance.find_by!(contract: domain[:contract])
    expect(receipt.integrity?).to be(true)
    expect { receipt.update!(source_digest: '0' * 64) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { domain[:contract].signed_document.attachment.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    wrong_contract = ActiveStorage::Attachment.new(record_type: 'JrcCrm::Contract', record_id: domain[:contract].id + 1,
                                                   name: 'signed_document', blob: receipt.signed_blob)
    wrong_name = ActiveStorage::Attachment.new(record: domain[:contract], name: 'other_file', blob: receipt.signed_blob)
    expect(wrong_contract).not_to be_valid
    expect(wrong_name).not_to be_valid
    expect(JrcBackoffice::PrivateBlob.protected?(receipt.signed_blob_id)).to be(true)
    expect { JrcBackoffice::SignatureAcceptance.where(id: receipt.id).delete_all }.to raise_error(ActiveRecord::StatementInvalid)
    expect { ActiveStorage::Attachment.where(id: domain[:contract].signed_document.attachment.id).delete_all }
      .to raise_error(ActiveRecord::StatementInvalid)
    expect do
      # Deliberately skip Ruby validation to exercise the PostgreSQL protection itself.
      # rubocop:disable Rails/SkipsModelValidations
      ActiveStorage::Attachment.insert_all!([{ record_type: 'JrcCrm::Contract', record_id: domain[:contract].id,
                                               name: 'other_file', blob_id: receipt.signed_blob_id, created_at: Time.current }])
      # rubocop:enable Rails/SkipsModelValidations
    end.to raise_error(ActiveRecord::StatementInvalid)
  end

  # rubocop:enable RSpec/MultipleExpectations
  it 'refuses quarantined evidence and a caller digest for another receipt' do
    scan_bundle(state: 'infected')
    expect { service.call(delivery_id: delivery.id, expected_source_digest: '0' * 64) }
      .to raise_error(JrcBackoffice::Signatures::DeliveryError, 'SIGNATURE_EVIDENCE_IDENTITY_MISMATCH')
    expect { service.call(delivery_id: delivery.id, expected_source_digest: bundle.source_digest) }
      .to raise_error(JrcBackoffice::Signatures::DeliveryError, 'SIGNATURE_ARTIFACT_QUARANTINED')
    expect(domain[:contract].reload.signature_status).not_to eq('signed')
  end

  it 'retains the immutable historical receipt but refuses it for changed current legal source data' do
    scan_bundle
    original = bundle.snapshot.deep_dup
    domain[:customer].update!(name: 'Synthetic legal name changed after sending')
    expect(JrcBackoffice::Signatures::EvidenceState.new(bundle).call.fetch(:state)).to eq('verified')
    expect { service.call(delivery_id: delivery.id, expected_source_digest: bundle.source_digest) }
      .to raise_error(JrcBackoffice::Signatures::DeliveryError, 'CONTRACT_SOURCE_CHANGED')
    expect(bundle.reload.snapshot).to eq(original)
    expect(domain[:contract].reload.signature_status).not_to eq('signed')
  end

  it 'keeps an accepted operation bound to its original connection when the configured default changes' do
    scan_bundle
    service.call(delivery_id: delivery.id, expected_source_digest: bundle.source_digest)
    original_connection = bundle.delivery.connection_id
    replacement = synthetic_delivery_connection(domain[:account])
    expect(replacement.id).not_to eq(original_connection)
    expect(bundle.reload.delivery.connection_id).to eq(original_connection)
    expect(JrcBackoffice::SignatureRelease.verified?(domain[:contract].reload)).to be(true)
  end

  it 'rechecks native unit authorization before accepting a signature' do
    scan_bundle
    domain[:account].jrc_crm_user_business_units.find_by!(user: domain[:actor], business_unit: domain[:unit]).update!(active: false)
    expect { service.call(delivery_id: delivery.id, expected_source_digest: bundle.source_digest) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(domain[:contract].reload.signature_status).not_to eq('signed')
    expect(JrcCrm::AuditEvent.where(account: domain[:account], event_type: 'backoffice_signature_evidence_accepted')).not_to exist
  end

  it 'does not replace a different previously registered signed file with the captured provider PDF' do
    scan_bundle
    contract = domain[:contract]
    contract.signed_document.attach(io: StringIO.new('%PDF-1.4 synthetic historical manual file'),
                                    filename: 'synthetic-historical-signature.pdf', content_type: 'application/pdf')
    contract.update!(signature_status: 'signed', signed_at: Time.current, signed_by_name: 'Synthetic historical signer')
    previous_blob = contract.signed_document.blob.id
    expect(JrcApprovals::SignatureEvidence.call(contract).fetch('state')).to eq('invalid')
    expect { service.call(delivery_id: delivery.id, expected_source_digest: bundle.source_digest) }
      .to raise_error(JrcBackoffice::Signatures::DeliveryError, 'SIGNATURE_HISTORY_CONFLICT')
    expect(contract.reload.signed_document.blob.id).to eq(previous_blob)
  end
end
