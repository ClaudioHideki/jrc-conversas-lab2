# Metadata is cheap enough for policy previews. Bytes are checked separately
# before creating a proposal, recording a decision or sending a contract.
class JrcBackoffice::AuthorityDocuments
  def initialize(account:, request_id:)
    @account = account
    @request_id = request_id
  end

  def capture(proofs)
    ids = proofs.flat_map { |row| row.fetch('document_version_ids') }.uniq.sort
    rows = versions.where(id: ids).order(:id).to_a
    raise ActiveRecord::RecordNotFound unless rows.length == ids.length && ids.length.between?(1, JrcBackoffice::AuthorityProofs::MAX_DOCUMENTS)

    data = rows.map { |version| observation(version) }
    if data.sum { |row| row['byte_size'].to_i } > JrcBackoffice::AuthorityProofs::MAX_TOTAL_BYTES
      raise ArgumentError, 'Use até 100 MB de evidências no conjunto da validação de poderes.'
    end

    data
  end

  def verify!(proofs, expected:)
    before = capture(proofs)
    raise JrcApprovals::Error, 'AUTHORITY_EVIDENCE_CHANGED' unless before == expected && before.all? { |row| row['ready'] }

    before.each { |row| JrcBackoffice::DocumentSafety.new(versions.find(row.fetch('id'))).bytes! }
    raise JrcApprovals::Error, 'AUTHORITY_EVIDENCE_CHANGED' unless capture(proofs) == before

    true
  rescue JrcBackoffice::DocumentSafety::NotClean, ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError
    raise JrcApprovals::Error, 'AUTHORITY_EVIDENCE_UNAVAILABLE'
  end

  private

  def versions
    JrcBackoffice::DocumentVersion.where(account_id: @account.id, backoffice_request_id: @request_id)
  end

  def observation(version)
    latest = versions.where(document_key: version.document_key).order(version: :desc).first
    scan = JrcBackoffice::DocumentSafety.new(version).current
    decision = version.decisions.order(id: :desc).first
    blob = version.file.attached? ? version.file.blob : nil
    data = { 'id' => version.id, 'document_key' => version.document_key, 'number' => version.version, 'sha256' => version.sha256,
             'blob_id' => blob&.id, 'byte_size' => blob&.byte_size, 'latest_id' => latest.id,
             'ready' => ready?(version, latest, scan, decision, blob) }
    data.merge(review_fields(version, scan, decision))
  end

  def review_fields(version, scan, decision)
    { 'scan_id' => scan&.id, 'scan_state' => scan&.state || 'unavailable', 'analysis_id' => version.analysis&.id,
      'decision_id' => decision&.id, 'decision_status' => decision&.status, 'decision_actor_id' => decision&.actor_id }
  end

  def ready?(version, latest, scan, decision, blob)
    latest.id == version.id && scan&.clean? == true && decision&.status == 'approved' && version.analysis.present? && blob.present?
  end
end
