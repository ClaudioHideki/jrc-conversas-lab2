# frozen_string_literal: true

# No signed storage URL: every read reauthorizes the current user, unit, version and latest observation.
class Api::V1::Accounts::JrcContactCenter::AudioBytesController < Api::V1::Accounts::JrcContactCenter::BaseController
  before_action -> { response.headers['Cache-Control'] = 'no-store' }
  before_action -> { authorize_contact_center!(:configure?) }

  def show
    access = JrcContactCenter::AudioLibraryAccess.new(context: pundit_user)
    result = JrcContactCenter::AudioBytes.new(access: access).call(asset_id: params[:audio_asset_id], version_id: params[:version_id])
    identify_response(result)
    send_data result.bytes, type: result.content_type, disposition: 'attachment'
  end

  private

  def identify_response(result)
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-JRC-Audio-Account'] = result.account_id
    response.headers['X-JRC-Audio-Unit'] = result.unit_id
    response.headers['X-JRC-Audio-Version'] = result.version_id
    response.headers['X-JRC-Audio-Inspection'] = result.inspection_id
    response.headers['X-JRC-Audio-SHA256'] = result.sha256
  end
end
