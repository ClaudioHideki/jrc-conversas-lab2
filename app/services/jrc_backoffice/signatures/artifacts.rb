# Only this server-side, authenticated provider path can create a bound bundle.
# A user-uploaded PDF or a completion webhook cannot become trusted evidence.
class JrcBackoffice::Signatures::Artifacts
  def initialize(account:, actor:, request_id:)
    @account = account
    @actor = actor
    @request_id = request_id
    @access = JrcBackoffice::ContractAccess.new(account: account, actor: actor)
  end

  def capture!(delivery_id:)
    raise JrcBackoffice::Signatures::DeliveryError, 'EVIDENCE_RETRIEVAL_REQUIRES_COMMITTED_CONTEXT' if ApplicationRecord.connection.transaction_open?

    delivery = JrcBackoffice::Signatures::Admissions.new(account: @account, actor: @actor, request_id: @request_id).scope.find(delivery_id)
    JrcBackoffice::AuthorityAccess.new(account: @account, actor: @actor).read_case!(delivery.authority_proposal)
    existing = bundles.find_by(delivery: delivery)
    if existing
      raise JrcBackoffice::Signatures::DeliveryError, 'SIGNATURE_ARTIFACT_INTEGRITY_INVALID' unless existing.integrity?

      return existing
    end

    observation = JrcBackoffice::Signatures::EvidenceObservation.new(delivery: delivery, actor: @actor).call
    @account.with_lock('FOR NO KEY UPDATE', requires_new: true) do
      request = @access.writable!(@access.request(@request_id))
      request.sales_order.with_lock('FOR NO KEY UPDATE') do
        request.with_lock('FOR NO KEY UPDATE') do
          contract = @access.contract!(request)
          contract.with_lock('FOR NO KEY UPDATE') { persist!(request, delivery, observation) }
        end
      end
    end
  end

  private

  def bundles
    JrcBackoffice::SignatureArtifactBundle.where(account_id: @account.id)
  end

  def persist!(request, delivery, observation)
    JrcBackoffice::Signatures::EvidenceObservation.new(delivery: delivery, actor: @actor).verify_binding!(observation.fetch(:binding))
    existing = bundles.find_by(delivery: delivery)
    return replay!(existing, observation) if existing

    documents = JrcBackoffice::Documents.new(request: request, actor: @actor)
    versions = observation.fetch(:artifacts).to_h do |kind, artifact|
      [kind, documents.receive_signature_file!(delivery: delivery, kind: kind, artifact: artifact)]
    end
    source = source_snapshot(delivery, observation, versions)
    source_json = JrcServiceDesk::CanonicalJson.dump(source)
    attributes = { delivery: delivery, contract_version: delivery.contract_version, signed_document: versions.fetch(:signed_document),
                   certificate_document: versions.fetch(:certificate), captured_by: @actor, source_snapshot: source_json,
                   source_digest: JrcBackoffice::SignatureArtifactBundle.digest(source) }
    record = bundles.create!(attributes)
    audit!(record, delivery)
    record
  end

  def audit!(record, delivery)
    metadata = { delivery_id: delivery.id, contract_version_id: delivery.contract_version_id, source_digest: record.source_digest }
    JrcCrm::AuditEvent.create!(account: @account, actor_type: 'User', actor_id: @actor.id, resource_type: record.class.name, resource_id: record.id,
                               event_type: 'backoffice_signature_evidence_captured', from_value: {}, to_value: {},
                               metadata: metadata)
  end

  def replay!(existing, observation)
    source = existing.snapshot
    same = existing.integrity? && source.fetch('binding') == observation.fetch(:binding) && source.fetch('signers') == observation.fetch(:signers) &&
           observation.fetch(:artifacts).all? { |kind, file| source.fetch('artifacts').fetch(kind.to_s).fetch('sha256') == file.fetch(:sha256) }
    raise JrcBackoffice::Signatures::DeliveryError, 'SIGNATURE_EVIDENCE_CONFLICT' unless same

    existing
  end

  def source_snapshot(delivery, observation, versions)
    { 'format_version' => 1, 'account_id' => @account.id, 'delivery_id' => delivery.id, 'contract_version_id' => delivery.contract_version_id,
      'signed_document_id' => versions.fetch(:signed_document).id, 'certificate_document_id' => versions.fetch(:certificate).id,
      'captured_by_id' => @actor.id, 'binding' => observation.fetch(:binding), 'signers' => observation.fetch(:signers),
      'observed_at' => observation.fetch(:observed_at), 'provider_state' => 'completion_reported',
      'artifacts' => versions.to_h do |kind, version|
        [kind.to_s, { 'document_version_id' => version.id, 'sha256' => version.sha256,
                      'blob_id' => version.file.blob.id, 'byte_size' => version.file.blob.byte_size }]
      end }
  end
end
