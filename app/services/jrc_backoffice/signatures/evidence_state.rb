# The provider receipt stays immutable. Current malware findings, version and
# contract source determine whether that receipt can authorize today's release.
class JrcBackoffice::Signatures::EvidenceState
  def initialize(bundle)
    @bundle = bundle
  end

  def call
    failure = provider_failure
    return result('invalid', failure) if failure

    scans = [@bundle.signed_document, @bundle.certificate_document].map { |version| JrcBackoffice::DocumentSafety.new(version).current }
    return result('invalid', 'SIGNATURE_ARTIFACT_QUARANTINED') if quarantined?(scans)
    return result('pending', 'SIGNATURE_ARTIFACT_SECURITY_PENDING') unless scans.all? { |scan| scan&.clean? }

    result('verified', nil)
  end

  def self.for_contract(contract)
    return { 'state' => 'pending_provider', 'evidence_digest' => nil } unless contract

    version = JrcBackoffice::ContractVersion.where(account_id: contract.account_id, contract_id: contract.id).order(number: :desc).first
    bundle = version && JrcBackoffice::SignatureArtifactBundle.find_by(account_id: contract.account_id, contract_version_id: version.id)
    return { 'state' => 'pending_provider', 'evidence_digest' => nil } unless bundle

    status = new(bundle).call
    state = status.fetch(:state)
    state = 'invalid' unless current_source?(contract, bundle) && matching_signed_file?(contract, bundle)
    { 'state' => state, 'evidence_digest' => state == 'verified' ? bundle.source_digest : nil }
  end

  def self.current_source?(contract, bundle)
    version = JrcBackoffice::ContractVersion.where(account_id: contract.account_id, contract_id: contract.id).order(number: :desc).first
    return false unless version&.id == bundle.contract_version_id

    roster = JrcBackoffice::SignerRoster.where(account_id: contract.account_id, contract_id: contract.id,
                                               backoffice_request_id: bundle.delivery.backoffice_request_id).order(revision: :desc).first
    roster&.id == version.signer_roster_id && JrcBackoffice::ContractSnapshot.digest(contract, signer_roster: roster) == version.source_digest
  end

  def self.matching_signed_file?(contract, bundle)
    return true unless contract.signature_status == 'signed'

    contract.signed_document.attached? && contract.signed_document.blob.id == bundle.signed_document.file.blob.id
  end

  private

  def quarantined?(scans)
    scans.any? { |scan| scan&.state.in?(%w[infected checksum_mismatch]) }
  end

  def provider_failure
    return 'SIGNATURE_ARTIFACT_INTEGRITY_INVALID' unless @bundle.integrity?
    return 'SIGNATURE_EVIDENCE_STATE_UNAVAILABLE' unless @bundle.snapshot['provider_state'] == 'completion_reported'
    return 'SIGNATURE_OPERATION_NOT_CURRENT' unless @bundle.delivery.state.in?(%w[sent completion_reported])

    nil
  end

  def result(state, code)
    { state: state, code: code, bundle_id: @bundle.id, contract_version_id: @bundle.contract_version_id,
      source_digest: @bundle.source_digest }
  end
end
