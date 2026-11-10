# Read the accepted exact-version artifact through the same operational scopes
# as its authenticated evidence view. This is not a sealed final dossier.
class JrcBackoffice::CompletionSignature
  def initialize(account:, actor:, request_id:)
    @account = account
    @actor = actor
    @request_id = request_id
  end

  def call(contract)
    return nil unless contract

    unavailable = { status: contract.signature_status, artifact_available: false }
    return unavailable unless JrcBackoffice::SignatureRelease.verified?(contract)

    receipt = JrcBackoffice::SignatureAcceptance.find_by(account_id: @account.id, contract_id: contract.id)
    return unavailable unless receipt&.integrity?

    bundle = receipt.bundle
    proof = JrcBackoffice::Signatures::EvidenceOperations.new(account: @account, actor: @actor, request_id: @request_id)
                                                         .summary(bundle.delivery_id)
    return unavailable unless proof.fetch(:accepted)

    unavailable.merge(artifact_available: true, contract_version_id: bundle.contract_version_id,
                      bundle_id: bundle.id, acceptance_id: receipt.id, source_digest: bundle.source_digest,
                      signed_document_version_id: bundle.signed_document_id, certificate_document_version_id: bundle.certificate_document_id)
  end
end
