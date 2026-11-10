class Api::V1::Accounts::Crm::BackofficeContractVersionsController < Api::V1::Accounts::Crm::BaseController
  rescue_from JrcBackoffice::ContractVersions::Changed do
    render json: { code: 'CONTRACT_SOURCE_CHANGED' }, status: :conflict
  end
  rescue_from ArgumentError do |error|
    render json: { message: error.message }, status: :unprocessable_entity
  end
  rescue_from ActiveStorage::IntegrityError, ActiveRecord::Encryption::Errors::Decryption do
    render json: { code: 'CONTRACT_DOCUMENT_UNAVAILABLE' }, status: :unprocessable_entity
  end
  prepend_before_action { response.headers['Cache-Control'] = 'no-store' }

  def index
    request = access.request(params[:backoffice_request_id])
    contract = request.contract && access.contract!(request)
    page = params.fetch(:page, 1).to_i.clamp(1, 10_000)
    rows = service.scope.order(id: :desc)
    data = version_rows(rows, page, contract)
    payload = { data: data, meta: { page: page, per_page: 10, total: rows.count },
                contract: contract_summary(contract) }.merge(generation_permissions(request, contract))
    access.request(params[:backoffice_request_id])
    render json: payload
  end

  def create
    version = service.create!(idempotency_key: params[:idempotency_key], expected_source_digest: params[:expected_source_digest],
                              change_reason: params[:change_reason])
    render json: version.serializable_hash, status: :created
  end

  def download
    version, bytes = service.download!(params[:version_id])
    response.headers['X-Content-Type-Options'] = 'nosniff'
    send_data bytes, filename: version.pdf_blob.filename.to_s, type: 'application/pdf', disposition: 'attachment'
  end

  def differences
    render json: { data: service.differences(params[:version_id]) }
  end

  private

  def generation_permissions(request, contract)
    { writable: access.writable?(request) && !delivery_active?(contract), signer_directory_access: signer_directory_access?(request, contract) }
  end

  def delivery_active?(contract)
    contract && JrcBackoffice::Signatures::DeliveryGuard.active(contract).exists?
  end

  def signer_directory_access?(request, contract)
    return true unless contract && JrcBackoffice::SignerRoster.exists?(account_id: Current.account.id,
                                                                       backoffice_request_id: request.id, contract_id: contract.id)

    JrcCustomers::ContactDirectory.new(account: Current.account, actor: Current.user).authorize!
    true
  rescue Pundit::NotAuthorizedError
    false
  end

  def version_rows(scope, page, contract)
    selected = scope.includes(:created_by).offset((page - 1) * 10).limit(10).to_a
    latest = JrcBackoffice::ContractVersion.where(account_id: crm_scope.id, contract_id: selected.map(&:contract_id))
                                           .group(:contract_id).maximum(:number)
    selected.map do |version|
      version.serializable_hash.merge('created_by_name' => version.created_by.name,
                                      'current' => contract&.id == version.contract_id && latest[version.contract_id] == version.number)
    end
  end

  def contract_summary(contract)
    return unless contract

    { id: contract.id, number: contract.contract_number, source_digest: service.source_digest(contract.id),
      signature_status: contract.signature_status }
  end

  def access
    JrcBackoffice::ContractAccess.new(account: Current.account, actor: Current.user)
  end

  def service
    JrcBackoffice::ContractVersions.new(account: Current.account, actor: Current.user, request_id: params[:backoffice_request_id])
  end
end
