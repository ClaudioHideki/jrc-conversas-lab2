# Read only the private files explicitly sealed into this case. Native Central
# reviewers get no generic Backoffice/document browsing or write permission.
class JrcBackoffice::AuthorityEvidence
  def initialize(proposal:, actor:)
    @proposal = proposal
    @actor = actor
    @access = JrcBackoffice::AuthorityAccess.new(account: proposal.account, actor: actor)
  end

  def contract_pdf!
    @access.read_case!(@proposal)
    version = @proposal.contract_version
    bytes = version.pdf_blob.download
    raise ActiveStorage::IntegrityError unless Digest::SHA256.hexdigest(bytes) == @proposal.snapshot.fetch('pdf_sha256')

    @access.read_case!(@proposal)
    audit!('contract_version_id' => version.id, 'sha256' => version.pdf_sha256)
    [version, bytes]
  end

  def document!(id)
    @access.read_case!(@proposal)
    allowed = @proposal.snapshot.fetch('proofs').flat_map { |row| row.fetch('document_version_ids') }.uniq
    version = JrcBackoffice::DocumentVersion.where(account_id: @proposal.account_id,
                                                   backoffice_request_id: @proposal.backoffice_request_id, id: allowed).find(id)
    bytes = JrcBackoffice::DocumentSafety.new(version).bytes!
    @access.read_case!(@proposal)
    audit!('document_version_id' => version.id, 'sha256' => version.sha256)
    [version, bytes]
  end

  private

  def audit!(data)
    JrcCrm::AuditEvent.create!(account: @proposal.account, actor_type: 'User', actor_id: @actor.id,
                               event_type: 'backoffice_authority_evidence_accessed', resource_type: 'JrcCrm::BackofficeRequest',
                               resource_id: @proposal.backoffice_request_id, from_value: {},
                               to_value: data.merge('authority_proposal_id' => @proposal.id),
                               metadata: { source: 'backoffice_contract_authority' })
  end
end
