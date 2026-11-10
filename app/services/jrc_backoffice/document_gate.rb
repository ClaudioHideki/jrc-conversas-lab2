# Resolve current file-backed state, never a cached metadata approval. Read
# previews avoid file I/O; critical transitions additionally verify exact bytes.
# v1 keeps its original evidence contract.
class JrcBackoffice::DocumentGate
  def self.statuses(request, verify_bytes_for: [])
    cached = (request.metadata || {}).fetch('document_statuses', {}).dup
    return cached unless request.workflow_version == 2

    keys = file_keys(request)
    rows = request.document_versions.where(account_id: request.account_id, document_key: keys)
      .select('DISTINCT ON (document_key) jrc_backoffice_document_versions.*').order(:document_key, version: :desc)
    current = rows.index_by(&:document_key)
    keys.each { |key| cached[key] = state(current[key], verify_bytes: verify_bytes_for.include?(key)) }
    cached
  end

  def self.check!(request, required_keys:)
    return unless request.workflow_version == 2

    keys = file_keys(request) & required_keys.map(&:to_s)
    return if keys.empty?
    states = statuses(request, verify_bytes_for: keys)
    return if keys.all? { |key| states[key] == 'approved' }

    raise JrcBackoffice::Requirements::Blocked, 'Required documents are missing, expired, rejected or not security-verified'
  end

  def self.file_keys(request)
    JrcBackoffice::Documents.new(request: request, actor: nil).requirements.map { |row| row.fetch('key') }
  end

  def self.state(version, verify_bytes:)
    return 'pending' unless version

    safety = JrcBackoffice::DocumentSafety.new(version)
    return 'quarantined' unless safety.current&.clean?

    safety.bytes! if verify_bytes
    version.status
  rescue JrcBackoffice::DocumentSafety::NotClean, ActiveStorage::IntegrityError
    'quarantined'
  end
  private_class_method :file_keys, :state
end
