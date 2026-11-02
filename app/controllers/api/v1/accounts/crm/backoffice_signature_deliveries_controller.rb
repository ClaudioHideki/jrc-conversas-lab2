class Api::V1::Accounts::Crm::BackofficeSignatureDeliveriesController < Api::V1::Accounts::Crm::BaseController
  prepend_before_action do
    response.headers['Cache-Control'] = 'no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
  end
  rescue_from ActiveRecord::Encryption::Errors::Decryption do
    render json: { code: 'SIGNATURE_HISTORY_UNAVAILABLE' }, status: :unprocessable_entity
  end

  def index
    render json: history.call(page: params[:page])
  end

  def show
    render json: history.show(params[:delivery_id], page: params[:page])
  end

  private

  def history
    JrcBackoffice::Signatures::History.new(account: Current.account, actor: Current.user, request_id: params[:backoffice_request_id])
  end
end
