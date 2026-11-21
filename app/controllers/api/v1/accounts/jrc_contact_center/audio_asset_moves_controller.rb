# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::AudioAssetMovesController < Api::V1::Accounts::JrcContactCenter::BaseController
  wrap_parameters false
  before_action -> { response.headers['Cache-Control'] = 'no-store' }
  before_action -> { authorize_contact_center!(:configure?) }

  def create
    unless request.request_parameters.keys.sort == %w[folder_id items unit_id]
      raise JrcContactCenter::OperationError, 'invalid_institutional_audio_move'
    end

    items = JrcContactCenter::AudioAssetMoves.new(context: pundit_user).call(
      unit_id: params[:unit_id], folder_id: params[:folder_id], items: params[:items]
    )
    render json: base_payload.merge(items: items)
  end
end
