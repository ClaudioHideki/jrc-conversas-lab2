require 'rails_helper'

# Synthetic acknowledgements/events exercise native contract/version guards.
# No provider request or legally valid signature is implied by these fixtures.
RSpec.describe JrcBackoffice::Signatures::DeliveryProjection, :approval_core, :authority_core, :signature_delivery_core do
  let(:domain) { admitted_signature_domain }
  let(:delivery) { domain.fetch(:delivery) }
  let(:contract) { domain.fetch(:contract) }
  let(:connection) { domain.fetch(:connection) }
  let(:external_id) { SecureRandom.uuid }

  before do
    raise 'Owned projection test database required' unless Rails.env.test? && ENV['POSTGRES_DATABASE'] == 'jrc_four_domains_schema_admission_test'

    delivery.events.create!(account: delivery.account, connection: connection, kind: 'send_confirmed', event_key: 'synthetic-ack',
                            external_id: external_id, source_snapshot: '{}')
    described_class.call(delivery)
  end

  it 'allows a new exact-source version after authenticated cancellation while retaining the canceled envelope and original PDF' do
    version = domain[:version]
    source = version.snapshot
    bytes = version.pdf_blob.download
    receipt = signature_receipt(connection: connection, event: 'envelope-voided', external_id: external_id)
    expect(JrcBackoffice::Signatures::Notifications.new(receipt_id: receipt.id).call).to eq(:processed)
    expect(described_class.call(delivery).state).to eq('canceled')
    revision = domain[:versions].create!(idempotency_key: SecureRandom.uuid,
                                         expected_source_digest: domain[:versions].source_digest(contract.id),
                                         change_reason: 'TESTE SINTÉTICO — Revisão após cancelamento confirmado.')
    expect([contract.reload.signature_status, contract.signature_external_id, revision.number]).to eq(['canceled', external_id, version.number + 1])
    expect([version.reload.snapshot, version.pdf_blob.download]).to eq([source, bytes])
    expect(delivery.reload.external_id).to eq(external_id)
    expect(JrcBackoffice::SignatureRelease.satisfied?(domain[:operation])).to be(false)
    expect(WebMock).not_to have_requested(:any, /docusign/)
  end

  it 'projects authenticated refusal as failed without creating signed evidence or claiming operational release' do
    receipt = signature_receipt(connection: connection, event: 'envelope-declined', external_id: external_id)
    JrcBackoffice::Signatures::Notifications.new(receipt_id: receipt.id).call
    described_class.call(delivery)
    state = [contract.reload.signature_status, contract.signature_external_id, contract.signed_document.attached?,
             JrcBackoffice::SignatureRelease.satisfied?(domain[:operation])]
    expect(state).to eq(['failed', external_id, false, false])
    described_class.call(delivery)
    expect([contract.reload.signature_status, delivery.state]).to eq(%w[failed declined])
    expect(WebMock).not_to have_requested(:any, /docusign/)
  end

  it 'rejects a stale-envelope projection rather than replacing the native reference to a newer send' do
    newer_reference = SecureRandom.uuid
    contract.update!(signature_external_id: newer_reference)
    receipt = signature_receipt(connection: connection, event: 'envelope-voided', external_id: external_id)
    JrcBackoffice::Signatures::Notifications.new(receipt_id: receipt.id).call
    expect do
      described_class.call(delivery)
    end.to raise_error(JrcBackoffice::Signatures::DeliveryError, 'DELIVERY_PROJECTION_CONFLICT')
    expect([contract.reload.signature_status, contract.signature_external_id]).to eq(['sent', newer_reference])
    expect(delivery.reload.state).to eq('canceled')
  end

  it 'preserves an already recorded signed contract and file even when a later provider cancellation is reported' do
    # An artificial legacy-like state solely tests preservation. The default
    # internal verifier still refuses to call this a valid operational signature.
    contract.signed_document.attach(io: StringIO.new(domain[:version].pdf_blob.download), filename: 'synthetic-existing.pdf',
                                    content_type: 'application/pdf')
    contract.update!(signature_status: 'signed', signed_at: Time.current, signed_by_name: 'TESTE SINTÉTICO — Não homologado')
    original_blob_id = contract.signed_document.blob.id
    receipt = signature_receipt(connection: connection, event: 'envelope-voided', external_id: external_id)
    JrcBackoffice::Signatures::Notifications.new(receipt_id: receipt.id).call
    described_class.call(delivery)
    expect([contract.reload.signature_status, contract.signed_document.blob.id, contract.signature_external_id])
      .to eq(['signed', original_blob_id, external_id])
    expect(JrcBackoffice::SignatureRelease.satisfied?(domain[:operation])).to be(false)
    expect(delivery.state).to eq('canceled')
    expect(WebMock).not_to have_requested(:any, /docusign/)
  end

  it 'advances to a newly admitted version after confirmed cancellation and ignores the old historical projection' do
    role = create(:custom_role, account: domain[:account], permissions: %w[jrc_crm jrc_approvals_request_create contact_manage])
    domain[:account].account_users.find_by!(user: domain[:actor]).update!(role: :agent, custom_role: role)
    receipt = signature_receipt(connection: connection, event: 'envelope-voided', external_id: external_id)
    JrcBackoffice::Signatures::Notifications.new(receipt_id: receipt.id).call
    described_class.call(delivery)
    revision = domain[:versions].create!(idempotency_key: SecureRandom.uuid,
                                         expected_source_digest: domain[:versions].source_digest(contract.id),
                                         change_reason: 'TESTE SINTÉTICO — Novo envio após cancelamento.')
    proposal = JrcBackoffice::AuthorityProposals.new(account: domain[:account], actor: domain[:actor], request_id: domain[:operation].id)
                                                .create!(**authority_input(revision, revision.signer_roster, domain[:document]))
    decision_id = delivery.snapshot.fetch('authority_approvals').first.fetch('decision_ids').first
    reviewer = JrcApprovals::Decision.find(decision_id).actor
    JrcApprovals::Request.where(account_id: delivery.account_id, resource_type: proposal.class.name, resource_id: proposal.id).each do |request|
      approval_vote(domain, reviewer, request)
    end
    admissions = JrcBackoffice::Signatures::Admissions.new(account: domain[:account], actor: domain[:actor], request_id: domain[:operation].id)
    next_delivery = admissions.create!(version_id: revision.id, authority_proposal_id: proposal.id,
                                       expected_connection_id: connection.id, expected_source_digest: revision.source_digest,
                                       idempotency_key: SecureRandom.uuid)
    next_id = SecureRandom.uuid
    # A simulated provider acknowledgement after real native approval/admission.
    next_delivery.events.create!(account: delivery.account, connection: connection, kind: 'send_confirmed', event_key: 'synthetic-new-ack',
                                 external_id: next_id, source_snapshot: '{}')
    described_class.call(next_delivery)
    expect([contract.reload.signature_status, contract.signature_external_id]).to eq(['sent', next_id])
    described_class.call(delivery)
    expect([contract.reload.signature_status, contract.signature_external_id]).to eq(['sent', next_id])
    expect([delivery.reload.external_id, next_delivery.reload.external_id]).to eq([external_id, next_id])
    expect([delivery.state, next_delivery.state]).to eq(%w[canceled sent])
    expect(JrcBackoffice::SignatureRelease.satisfied?(domain[:operation])).to be(false)
    expect(WebMock).not_to have_requested(:any, /docusign/)
  end
end
