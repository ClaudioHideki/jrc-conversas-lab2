class Api::V1::Accounts::JrcAi::LegacyReservationsController < Api::V1::Accounts::JrcAi::BaseController
  before_action :ensure_ai_administrator!
  rescue_from JrcNico::LegacyReservationReview::Conflict, with: :conflict
  rescue_from ArgumentError, ActiveRecord::RecordInvalid, with: :invalid

  def index
    render json: JrcNico::LegacyReservations.new(member: Current.account_user).report(period: params[:period])
  end

  def simulate
    render json: review.call(type: params[:type], id: params[:id], decision: decision)
  end

  def reconcile
    render json: review.call(type: params[:type], id: params[:id], decision: decision, apply: true,
                            authorized: params[:authorized] == true, simulation_token: params[:simulation_token])
  end

  private

  def review
    JrcNico::LegacyReservationReview.new(member: Current.account_user)
  end

  def decision
    params.require(:decision).permit(:request_id, :fingerprint, :classification, :source, :justification, :provider_id, :model,
                                    :conservative_upper_bound, :runtime_outcome, usage_event_ids: [], excluded_usage_event_ids: [],
                                    evidence: [:reference, :sha256], usage: [:input_tokens, :output_tokens, :total_tokens]).to_h
  end

  def invalid
    render json: { error: 'invalid_legacy_review' }, status: :unprocessable_entity
  end

  def conflict
    render json: { error: 'legacy_review_conflict', message: 'Refaça a simulação e confira o estado e as evidências do registro.' }, status: :conflict
  end
end
