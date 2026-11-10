class Api::V1::Accounts::Crm::BackofficeDocumentsController < Api::V1::Accounts::Crm::BaseController
  before_action :set_request
  rescue_from ArgumentError do |error|
    render json: { message: error.message }, status: :unprocessable_entity
  end
  rescue_from JrcBackoffice::Documents::Conflict do |error|
    render json: { code: 'DOCUMENT_REVIEW_CONFLICT', message: error.message }, status: :conflict
  end
  rescue_from JrcBackoffice::DocumentSafety::NotClean, ActiveStorage::IntegrityError do
    render json: { code: 'DOCUMENT_QUARANTINED', message: 'Documento bloqueado até a verificação de segurança do arquivo.' },
           status: :unprocessable_entity
  end
  prepend_before_action { response.headers['Cache-Control'] = 'no-store' }

  def index
    requirements = service.requirements
    selected = requirements.find { |row| row['key'] == params[:document_key] } || requirements.first
    scope = versions.where(document_key: selected&.fetch('key')).order(version: :desc)
    data = document_page(scope).merge(requirements: requirements, selected_key: selected&.fetch('key'))
    access.request(@request.id)
    render json: data
  end

  def create
    version = service.upload!(key: params[:document_key].to_s, file: params[:file], idempotency_key: params[:idempotency_key])
    access.request(@request.id)
    render json: serialize(version), status: :created
  end

  def download
    version = versions.find(params[:version_id])
    bytes = JrcBackoffice::DocumentSafety.new(version).bytes!
    access.request(@request.id)
    audit_access!(version)
    response.headers['Cache-Control'] = 'no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    send_data bytes, filename: version.file.filename.to_s, type: version.file.content_type, disposition: 'attachment'
  end

  def decide
    version = versions.find(params[:version_id])
    options = {}
    options[:expires_on] = params[:expires_on] if params.key?(:expires_on)
    options[:expected_decision_id] = params[:expected_decision_id] if params.key?(:expected_decision_id)
    service.decide!(version: version, status: params[:status], reason: params[:reason], **options)
    access.request(@request.id)
    render json: serialize(version.reload)
  end

  def recheck
    raise ArgumentError, 'Reabra a solicitação antes de verificar seus documentos.' if @request.status.in?(%w[completed canceled rejected])

    version = versions.find(params[:version_id])
    job = JrcBackoffice::DocumentPreanalysisJob.perform_later(version.id)
    if job.is_a?(ActiveJob::Base) && job.successfully_enqueued?
      access.request(@request.id)
      render json: { id: version.id, status: 'queued' }, status: :accepted
    else
      render json: { code: 'DOCUMENT_CHECK_NOT_QUEUED' }, status: :service_unavailable
    end
  end

  private

  def document_page(scope)
    count = scope.count
    pages = [(count / 5.0).ceil, 1].max
    page = params[:page].to_i.clamp(1, pages)
    rows = scope.includes(:analysis, file_attachment: :blob).offset((page - 1) * 5).limit(5)
    { data: rows.map { |version| serialize(version) }, meta: { page: page, pages: pages, total: count, per_page: 5 } }
  end

  def audit_access!(version)
    JrcCrm::AuditEvent.create!(account: crm_scope, actor_type: 'User', actor_id: Current.user.id,
                               event_type: 'backoffice_document_accessed', resource_type: @request.class.name, resource_id: @request.id,
                               from_value: {}, to_value: { version_id: version.id }, metadata: { source: 'backoffice_documents' })
  end

  def set_request
    @request = access.request(params[:backoffice_request_id])
  end

  def access
    JrcBackoffice::ContractAccess.new(account: Current.account, actor: Current.user)
  end

  def service
    JrcBackoffice::Documents.new(request: @request, actor: Current.user)
  end

  def versions
    @request.document_versions.where(account_id: Current.account.id)
  end

  def serialize(version)
    inspection = JrcBackoffice::DocumentSafety.new(version).current
    decision = version.current_decision
    { id: version.id, document_key: version.document_key, version: version.version, status: version.status(decision: decision),
      safety: { state: inspection&.state || 'pending', checked_at: inspection&.created_at },
      decision_revision: decision&.id, expires_on: decision&.expires_on,
      validity_timezone: decision&.validity_timezone,
      current: !versions.where(document_key: version.document_key).exists?(['version > ?', version.version]),
      filename: version.file.filename.to_s, byte_size: version.file.byte_size, created_at: version.created_at }.merge(review_details(version))
  end

  def review_details(version)
    { analysis: version.analysis&.attributes&.slice('analyzer_version', 'state', 'evidence', 'created_at'),
      decisions: version.decisions.order(id: :desc).limit(10).map { |row| row.attributes.slice('id', 'actor_id', 'status', 'reason', 'created_at', 'expires_on', 'validity_timezone') } }
  end
end
