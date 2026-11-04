class Api::V1::Accounts::Relationship::DocumentsController < Api::V1::Accounts::Relationship::BaseController
  rescue_from JrcServiceDesk::AttachmentScanError do
    render json: { errors: ['Document is quarantined. A valid clean antivirus scan is required.'] }, status: :conflict
  end

  def index
    scope = service.scope.where(assignment_id: relationship_context.assignment(params.require(:assignment_id)).id)
    records, meta = page(scope.includes(assignment: :owner).order(updated_at: :desc, id: :desc))
    render json: { payload: records.map { |record| present(record, include_versions: false) }, meta: meta }
  end

  def show
    render json: present(service.scope.find(params[:id]), include_versions: true)
  end

  def create
    upload
  end

  def version
    upload
  end

  def download
    blob, bytes = service.download!(document_id: params[:id], version_id: params[:version_id])
    response.headers['Cache-Control'] = 'no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    send_data bytes, filename: blob.filename.to_s, type: 'application/octet-stream', disposition: 'attachment'
  end

  private

  def service
    @service ||= JrcRelationship::CustomerDocuments.new(relationship_context)
  end

  def upload
    attrs = params.require(:document).permit(:title, :category, :valid_until, :change_reason).to_h
    document = service.upload!(assignment_id: params.require(:assignment_id), attributes: attrs,
                               upload: params.require(:file), document_id: params[:id])
    render json: present(document, include_versions: true), status: :created
  end

  def present(document, include_versions:)
    versions = document.versions.includes(:uploaded_by, file_attachment: :blob).order(number: :desc)
    data = { id: document.id, assignment_id: document.assignment_id, title: document.title, category: document.category, status: document.status }
    owner = document.assignment.owner
    data[:portfolio_owner] = owner && { id: owner.id, name: owner.name }
    selected, meta = include_versions ? page(versions) : [versions.limit(1), nil]
    data[:versions_meta] = meta if include_versions
    data[:versions] = selected.map { |version| present_version(version) }
    data
  end

  def present_version(version)
    blob = version.file.blob
    { id: version.id, number: version.number, valid_until: version.valid_until, expired: version.valid_until && version.valid_until < Date.current,
      filename: blob.filename.to_s, byte_size: blob.byte_size, uploaded_at: version.created_at, change_reason: version.change_reason,
      checksum: blob.checksum, checksum_algorithm: 'MD5 (Active Storage integrity)', uploaded_by_id: version.uploaded_by_id,
      uploaded_by: { id: version.uploaded_by_id, name: version.uploaded_by.name },
      scan_state: blob.metadata['service_desk_scan_state'] || 'pending', download_available: JrcServiceDesk::AttachmentScanner.clean?(blob) }
  end
end
