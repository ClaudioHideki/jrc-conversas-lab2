class Api::V1::Accounts::Crm::BackofficeDocumentsController < Api::V1::Accounts::Crm::BaseController
  before_action :set_request
  rescue_from ArgumentError do |error|
    render json: { message: error.message }, status: :unprocessable_entity
  end

  def index
    requirements = service.requirements
    selected = requirements.find { |row| row['key'] == params[:document_key] } || requirements.first
    scope = @request.document_versions.where(document_key: selected&.fetch('key')).order(version: :desc)
    count = scope.count
    pages = [(count / 5.0).ceil, 1].max
    page = params[:page].to_i.clamp(1, pages)
    render json: { requirements: requirements, selected_key: selected&.fetch('key'),
      data: scope.includes(:analysis, :decisions, file_attachment: :blob).offset((page - 1) * 5).limit(5).map { |version| serialize(version) },
      meta: { page: page, pages: pages, total: count, per_page: 5 } }
  end

  def create
    version = service.upload!(key: params[:document_key].to_s, file: params[:file], idempotency_key: params[:idempotency_key])
    render json: serialize(version), status: :created
  end

  def download
    version = @request.document_versions.find(params[:version_id])
    JrcCrm::AuditEvent.create!(account: crm_scope, actor_type: 'User', actor_id: Current.user.id,
      event_type: 'backoffice_document_accessed', resource_type: @request.class.name, resource_id: @request.id,
      from_value: {}, to_value: { version_id: version.id }, metadata: { source: 'backoffice_documents' })
    response.headers['Cache-Control'] = 'no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    send_data version.file.download, filename: version.file.filename.to_s, type: version.file.content_type, disposition: 'attachment'
  end

  def decide
    version = @request.document_versions.find(params[:version_id])
    service.decide!(version: version, status: params[:status], reason: params[:reason])
    render json: serialize(version.reload)
  end

  private

  def set_request
    @request = visible_to_current_user(crm_scope.jrc_crm_backoffice_requests).find(params[:backoffice_request_id])
  end

  def service
    JrcBackoffice::Documents.new(request: @request, actor: Current.user)
  end

  def serialize(version)
    { id: version.id, document_key: version.document_key, version: version.version, status: version.status,
      filename: version.file.filename.to_s, byte_size: version.file.byte_size, created_at: version.created_at,
      current: !@request.document_versions.where(document_key: version.document_key).where('version > ?', version.version).exists?,
      analysis: version.analysis&.attributes&.slice('analyzer_version', 'state', 'evidence', 'created_at'),
      decisions: version.decisions.order(id: :desc).limit(10).map { |row| row.attributes.slice('id', 'actor_id', 'status', 'reason', 'created_at') } }
  end
end
