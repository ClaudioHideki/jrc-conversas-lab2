require 'rails_helper'

# Connector replies only; no external requests and no actual signed PDFs.
RSpec.describe JrcBackoffice::Docusign::Evidence do
  let(:adapter) { instance_double(JrcBackoffice::Docusign::Adapter) }
  let(:client) { instance_double(JrcBackoffice::Docusign::Client) }
  let(:external_id) { SecureRandom.uuid }
  let(:status) { { external_id: external_id, state: 'completion_reported', provider_state: 'completed' } }
  let(:documents) { { 'envelopeDocuments' => [{ 'documentId' => '1' }, { 'documentId' => 'certificate' }] } }
  let(:signers) { [{ id: '1', name: 'Synthetic signer', email: 'signer@example.test', completed: true, signed_at: Time.current.iso8601(6) }] }
  let(:service) { described_class.new(adapter: adapter, client: client) }

  before do
    allow(adapter).to receive(:status).with(external_id).and_return(status)
    allow(adapter).to receive(:recipients).with(external_id).and_return(signers: signers)
    allow(client).to receive(:documents).with(external_id).and_return(documents)
    allow(adapter).to receive(:document).with(external_id, kind: :final_document).and_return('%PDF-1.4 synthetic final')
    allow(adapter).to receive(:document).with(external_id, kind: :certificate).and_return('%PDF-1.4 synthetic certificate')
  end

  it 'reads final document and separate certificate only for an unchanged completed one-contract envelope' do
    expect(service.call(external_id)).to include(external_id: external_id, state: 'completion_reported', document_references: ['1'],
                                                 signed_document: '%PDF-1.4 synthetic final', certificate: '%PDF-1.4 synthetic certificate')
    expect(adapter).to have_received(:status).with(external_id).twice
    expect(client).to have_received(:documents).with(external_id).twice
  end

  it 'rejects an additional document before downloading any PDF' do
    documents['envelopeDocuments'] << { 'documentId' => '2' }
    expect(adapter).not_to receive(:document)
    expect { service.call(external_id) }.to raise_error(JrcBackoffice::Signatures::ProviderError) { |error|
      expect(error.code).to eq('PROVIDER_DOCUMENT_BINDING_INVALID')
    }
  end

  it 'rejects a recipient change during storage I/O instead of returning a stable-looking bundle' do
    allow(adapter).to receive(:recipients).with(external_id).and_return({ signers: signers }, { signers: [] })
    expect { service.call(external_id) }.to raise_error(JrcBackoffice::Signatures::ProviderError) { |error|
      expect(error.code).to eq('PROVIDER_EVIDENCE_CHANGED')
    }
  end

  it 'refuses incomplete provider state and malformed document manifests' do
    status[:state] = 'waiting'
    expect { service.call(external_id) }.to raise_error(JrcBackoffice::Signatures::ProviderError) { |error|
      expect(error.code).to eq('SIGNATURE_NOT_COMPLETED')
    }
    status[:state] = 'completion_reported'
    documents['envelopeDocuments'] = nil
    expect { service.call(external_id) }.to raise_error(JrcBackoffice::Signatures::ProviderError) { |error|
      expect(error.code).to eq('PROVIDER_DOCUMENT_BINDING_INVALID')
    }
  end
end
