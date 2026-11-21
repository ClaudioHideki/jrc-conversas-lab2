# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::AudioUsagesController < Api::V1::Accounts::JrcContactCenter::BaseController
  before_action -> { response.headers['Cache-Control'] = 'no-store' }
  before_action -> { authorize_contact_center!(:configure?) }

  def show
    usages = JrcContactCenter::AudioIvrUsages.new(context: pundit_user, asset_id: params[:audio_asset_id])
    params[:page] = 1 if params[:page].blank?
    params[:per_page] = params.fetch(:per_page, 10).to_i.clamp(1, 20)
    records = usages.relation.order(created_at: :desc, id: :desc)
    payload = list_payload(records) { |version| usages.present(version) }
    render json: payload.merge(audio_asset_id: usages.asset.id.to_s, unit_id: usages.asset.unit_id.to_s,
                               coverage: 'current_local_ivr_drafts_only', provider_configuration_verified: false)
  end
end
