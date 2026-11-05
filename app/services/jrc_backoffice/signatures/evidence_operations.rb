# Interactive authorization/summary/download boundary. GET performs no provider
# I/O; capture and acceptance remain explicit independent commands.
class JrcBackoffice::Signatures::EvidenceOperations
  KINDS = %w[signed_document certificate].freeze

  def initialize(account:, actor:, request_id:)
    @account = account
    @actor = actor
    @request_id = request_id
    @access = JrcBackoffice::ContractAccess.new(account: account, actor: actor)
  end

  def summary(delivery_id)
    delivery = authorized_delivery!(delivery_id)
    request = @access.request(@request_id)
    contract = @access.contract!(request)
    bundle = bundles.find_by(delivery: delivery)
    writable = @access.writable?(request)
    return missing_summary(delivery, writable) unless bundle

    result = received_summary(contract, bundle, writable)
    authorized_delivery!(delivery_id)
    result
  end

  def download(delivery_id:, kind:)
    raise ArgumentError, 'Unsupported signature artifact' unless KINDS.include?(kind)

    delivery = authorized_delivery!(delivery_id)
    bundle = bundles.find_by!(delivery: delivery)
    raise JrcBackoffice::Signatures::DeliveryError, 'SIGNATURE_ARTIFACT_INTEGRITY_INVALID' unless bundle.integrity?

    version = artifact(bundle, kind)
    bytes = JrcBackoffice::DocumentSafety.new(version).bytes!
    authorized_delivery!(delivery_id)
    [bundle, bytes]
  end

  private

  def received_summary(contract, bundle, writable)
    proof = effective_proof(contract, bundle)
    current = JrcBackoffice::Signatures::EvidenceState.current_source?(contract, bundle)
    verified = proof.fetch(:state) == 'verified'
    accepted = current && contract.signature_status == 'signed' && verified
    proof.merge(bundle: bundle.serializable_hash, current_source: current, accepted: accepted,
                can_capture: false, can_accept: writable && current && contract.signature_status != 'signed' && verified,
                version_number: bundle.contract_version.number, downloads: downloads(bundle))
  end

  def effective_proof(contract, bundle)
    proof = JrcBackoffice::Signatures::EvidenceState.new(bundle).call
    current = JrcBackoffice::Signatures::EvidenceState.current_source?(contract, bundle)
    matches = JrcBackoffice::Signatures::EvidenceState.matching_signed_file?(contract, bundle)
    proof = proof.merge(state: 'invalid', code: 'SIGNATURE_HISTORY_CONFLICT') unless matches
    proof = proof.merge(state: 'source_changed', code: 'CONTRACT_SOURCE_CHANGED') if !current && proof.fetch(:state) == 'verified'
    proof
  end

  def bundles
    JrcBackoffice::SignatureArtifactBundle.where(account_id: @account.id)
  end

  def authorized_delivery!(id)
    delivery = JrcBackoffice::Signatures::Admissions.new(account: @account, actor: @actor, request_id: @request_id).scope.find(id)
    JrcBackoffice::AuthorityAccess.new(account: @account, actor: @actor).read_case!(delivery.authority_proposal)
    delivery
  end

  def missing_summary(delivery, writable)
    { state: 'not_received', code: nil, bundle: nil, accepted: false, can_accept: false, downloads: [],
      can_capture: writable && delivery.external_id.present? && delivery.state.in?(%w[sent completion_reported]) }
  end

  def downloads(bundle)
    return [] unless bundle.integrity?

    KINDS.map do |kind|
      { kind: kind, available: JrcBackoffice::DocumentSafety.new(artifact(bundle, kind)).current&.clean? == true }
    end
  end

  def artifact(bundle, kind)
    kind == 'signed_document' ? bundle.signed_document : bundle.certificate_document
  end
end
