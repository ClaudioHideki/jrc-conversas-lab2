class Api::V1::Accounts::Relationship::DocumentsController < Api::V1::Accounts::Relationship::BaseController
  rescue_from JrcServiceDesk::AttachmentScanError do
    render json: { errors: ['Document is quarantined. A valid clean antivirus scan is required.'] }, status: :conflict
  end

  def index
    scope = service.scope.where(assignment_id: relationship_context.assignment(params.require(:assignment_id)).id)
    records, meta = page(scope.includes(:responsible, assignment: :owner).order(updated_at: :desc, id: :desc))
    records = records.to_a
    versions = service.latest_versions(document_ids: records.map(&:id))
    render json: { payload: records.map { |record| present(record, include_versions: false, latest_version: versions[record.id]) }, meta: meta,
                   requirements: JrcRelationship::DocumentRequirements.new(relationship_context).call(assignment_id: params[:assignment_id]) }
  end

  def show
    render json: present(service.scope.find(params[:id]), include_versions: true)
  end

  def create
    upload
  end

  def update
    input = params.require(:document)
    if input.key?(:responsible_id) && [String, Integer, NilClass].none? { |type| input[:responsible_id].is_a?(type) }
      raise ArgumentError, 'Responsible must be one user identifier'
    end

    values = input.permit(:responsible_id, :status, :revision, :reason, :requirement_key).to_h
    document = JrcRelationship::DocumentMetadata.new(relationship_context).update!(document_id: params[:id], attributes: values)
    render json: present(document, include_versions: true)
  end

  def responsibles
    scope = JrcRelationship::DocumentMetadata.new(relationship_context).responsibles(document_id: params[:id])
    query = params[:q].to_s.strip.first(100)
    scope = scope.where('users.name ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(query)}%") if query.present?
    records, meta = page(scope.order(:name, :id))
    render json: { payload: records.map { |user| { id: user.id, name: user.name, eligible: user.active_for_authentication? } }, meta: meta }
  end

  def history
    history = JrcRelationship::DocumentHistory.new(relationship_context)
    records, meta = page(history.scope(document_id: params[:id], kind: params[:kind].presence).order(created_at: :desc, id: :desc))
    response.headers['Cache-Control'] = 'no-store'
    render json: { payload: history.present(records), meta: meta }
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
    attrs = params.require(:document).permit(:title, :category, :valid_until, :change_reason, :requirement_key).to_h
    document = service.upload!(assignment_id: params.require(:assignment_id), attributes: attrs,
                               upload: params.require(:file), document_id: params[:id])
    render json: present(document, include_versions: true), status: :created
  end

  def present(document, include_versions:, latest_version: nil)
    data = { id: document.id, assignment_id: document.assignment_id, title: document.title, category: document.category, status: document.status }
    data.merge!(document_metadata(document))
    selected, meta = if include_versions
                       page(document.versions.includes(:uploaded_by, file_attachment: :blob).order(number: :desc))
                     else
                       [[latest_version].compact, nil]
                     end
    data[:versions_meta] = meta if include_versions
    data[:versions] = selected.map { |version| present_version(version) }
    data
  end

  def document_metadata(document)
    owner = document.assignment.owner
    responsible = document.responsible
    { revision: document.lock_version, requirement_key: document.requirement_key,
      responsible: responsible && { id: responsible.id, name: responsible.name },
      portfolio_owner: owner && { id: owner.id, name: owner.name } }
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
