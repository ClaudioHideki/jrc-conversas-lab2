# Read-only provider observations, never an internal signed/activation decision.
# The installed connector sends one contract document, with documentId=1.
class JrcBackoffice::Docusign::Evidence
  def initialize(adapter:, client:)
    @adapter = adapter
    @client = client
  end

  def call(external_id)
    before = facts(external_id)
    signed = @adapter.document(external_id, kind: :final_document)
    certificate = @adapter.document(external_id, kind: :certificate)
    after = facts(external_id)
    fail!('PROVIDER_EVIDENCE_CHANGED') unless before == after

    before.merge(signed_document: signed, certificate: certificate, observed_at: Time.current.iso8601(6))
  end

  private

  def facts(id)
    status = @adapter.status(id)
    fail!('SIGNATURE_NOT_COMPLETED') unless status.fetch(:state) == 'completion_reported'

    { external_id: status.fetch(:external_id), state: status.fetch(:state), document_references: document_refs!(id),
      signers: @adapter.recipients(id).fetch(:signers) }
  rescue KeyError, TypeError
    fail!('PROVIDER_RESPONSE_INVALID')
  end

  def document_refs!(id)
    documents = @client.documents(id).fetch('envelopeDocuments')
    valid = documents.is_a?(Array) && documents.size.between?(1, 2) && documents.all?(Hash)
    fail!('PROVIDER_DOCUMENT_BINDING_INVALID') unless valid

    ids = documents.pluck('documentId')
    refs = ids.reject { |value| value == 'certificate' }
    fail!('PROVIDER_DOCUMENT_BINDING_INVALID') unless ids.uniq == ids && refs == ['1']

    refs
  end

  def fail!(code)
    raise JrcBackoffice::Signatures::ProviderError.new(code: code)
  end
end
