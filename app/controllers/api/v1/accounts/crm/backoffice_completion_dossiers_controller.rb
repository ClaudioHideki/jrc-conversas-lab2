class Api::V1::Accounts::Crm::BackofficeCompletionDossiersController < Api::V1::Accounts::Crm::BackofficeCompletionPackagesController
  rescue_from JrcBackoffice::CompletionDossiers::Unavailable do
    render json: { code: 'DOSSIER_INCOMPLETE' }, status: :conflict
  end

  def show
    render json: service.show(page: params[:page])
  end

  def create
    digest = params.require(:completion_dossier).permit(:expected_manifest_digest).fetch(:expected_manifest_digest)
    row = service.seal!(expected_manifest_digest: digest)
    render json: row.presentation, status: :created
  end

  def download
    row, bytes = service.download(params[:dossier_id])
    response.headers['X-Content-Type-Options'] = 'nosniff'
    send_data bytes, filename: "backoffice-#{row.backoffice_request_id}-sealed-v#{row.number}.tar.gz",
                     type: 'application/gzip', disposition: 'attachment'
  end

  private

  def service
    JrcBackoffice::CompletionDossiers.new(account: Current.account, actor: Current.user, request_id: params[:backoffice_request_id])
  end
end
