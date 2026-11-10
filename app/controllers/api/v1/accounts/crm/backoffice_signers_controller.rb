class Api::V1::Accounts::Crm::BackofficeSignersController < Api::V1::Accounts::Crm::BaseController
  prepend_before_action { response.headers['Cache-Control'] = 'no-store' }
  rescue_from JrcBackoffice::SignerRosters::Changed do
    render json: { code: 'CONTRACT_SIGNERS_CHANGED', message: 'A proposta ou o contexto mudou. Atualize antes de continuar.' }, status: :conflict
  end
  rescue_from ArgumentError do |error|
    render json: { message: error.message }, status: :unprocessable_entity
  end
  rescue_from ActiveRecord::Encryption::Errors::Decryption do
    render json: { code: 'CONTRACT_SIGNERS_UNAVAILABLE' }, status: :unprocessable_entity
  end

  def index
    render json: service.overview(page: params[:page])
  end

  def create
    record = service.create!(**signer_params.to_h.symbolize_keys)
    render json: record.serializable_hash, status: :created
  end

  def contacts
    selector = JrcBackoffice::SignerContacts.new(account: Current.account, actor: Current.user, request_id: params[:backoffice_request_id])
    render json: selector.call(party: params[:party], query: params[:q], page: params[:page])
  end

  private

  def signer_params
    params.require(:signer_roster).permit(:idempotency_key, :expected_revision, :expected_source_digest,
                                          :customer_mode, :issuer_mode, :change_reason, signers: %i[contact_id party])
  end

  def service
    JrcBackoffice::SignerRosters.new(account: Current.account, actor: Current.user, request_id: params[:backoffice_request_id])
  end
end
