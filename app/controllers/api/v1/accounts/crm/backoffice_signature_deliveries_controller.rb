class Api::V1::Accounts::Crm::BackofficeSignatureDeliveriesController < Api::V1::Accounts::Crm::BaseController
  prepend_before_action do
    response.headers['Cache-Control'] = 'no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
  end
  rescue_from ActiveRecord::Encryption::Errors::Decryption do
    render json: { code: 'SIGNATURE_HISTORY_UNAVAILABLE' }, status: :unprocessable_entity
  end
  rescue_from JrcBackoffice::Signatures::ProviderError do |exception|
    render json: { code: exception.code }, status: :conflict
  end

  def index
    render json: history.call(page: params[:page])
  end

  def show
    render json: history.show(params[:delivery_id], page: params[:page])
  end

  def preparation
    render json: JrcBackoffice::Signatures::Preparation.new(account: Current.account, actor: Current.user,
                                                            request_id: params[:backoffice_request_id]).call
  end

  def create
    record = admissions.create!(**delivery_params.to_h.symbolize_keys)
    # Admissions has returned from its native transaction. A broker failure
    # leaves the same durable intent recoverable; retry uses the same key.
    JrcBackoffice::SignatureDispatchJob.perform_later(record.id) if record.state == 'prepared'
    render json: record.serializable_hash, status: :accepted
  end

  def cancel_prepared
    record = admissions.cancel_prepared!(params[:delivery_id])
    render json: record.serializable_hash
  end

  private

  def admissions
    JrcBackoffice::Signatures::Admissions.new(account: Current.account, actor: Current.user, request_id: params[:backoffice_request_id])
  end

  def delivery_params
    params.require(:signature_delivery).permit(:version_id, :authority_proposal_id, :expected_connection_id,
                                               :expected_source_digest, :idempotency_key)
  end

  def history
    JrcBackoffice::Signatures::History.new(account: Current.account, actor: Current.user, request_id: params[:backoffice_request_id])
  end
end
