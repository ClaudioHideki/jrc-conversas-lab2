class Api::V1::Accounts::Crm::BackofficeCompletionPackagesController < Api::V1::Accounts::Crm::BaseController
  rescue_from JrcBackoffice::CompletionReport::NotCompleted do
    render json: { code: 'REQUEST_NOT_COMPLETED' }, status: :unprocessable_entity
  end
  rescue_from JrcBackoffice::CompletionReport::TooLarge do
    render json: { code: 'PACKAGE_TOO_LARGE' }, status: :unprocessable_entity
  end
  rescue_from JrcBackoffice::CompletionPackage::Changed, JrcBackoffice::DocumentSafety::NotClean do
    render json: { code: 'PACKAGE_CHANGED' }, status: :conflict
  end
  rescue_from ActiveStorage::IntegrityError do
    render json: { code: 'PACKAGE_FILE_INTEGRITY' }, status: :conflict
  end
  rescue_from ActiveStorage::FileNotFoundError do
    render json: { code: 'PACKAGE_FILE_UNAVAILABLE' }, status: :unprocessable_entity
  end
  prepend_before_action { response.headers['Cache-Control'] = 'no-store' }

  def show
    render json: service.manifest
  end

  def download
    bytes = service.download
    response.headers['X-Content-Type-Options'] = 'nosniff'
    send_data bytes, filename: "backoffice-#{params[:backoffice_request_id].to_i}-documents.tar.gz",
                     type: 'application/gzip', disposition: 'attachment'
  end

  private

  def service
    JrcBackoffice::CompletionPackage.new(account: Current.account, actor: Current.user, request_id: params[:backoffice_request_id])
  end
end
