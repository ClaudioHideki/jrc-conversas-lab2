# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::AudioArchivesController < Api::V1::Accounts::JrcContactCenter::BaseController
  wrap_parameters false
  before_action -> { response.headers['Cache-Control'] = 'no-store' }
  before_action -> { authorize_contact_center!(:configure?) }

  def create
    raise JrcContactCenter::OperationError, 'invalid_institutional_audio_archive' unless request.request_parameters.keys == ['items']

    result = JrcContactCenter::AudioArchives.new(context: pundit_user).call(items: params[:items])
    identify_response(result)
    send_data result.bytes, type: 'application/zip', filename: 'audios-institucionais.zip', disposition: 'attachment'
  end

  private

  def identify_response(result)
    headers = response.headers
    headers['X-Content-Type-Options'] = 'nosniff'
    headers['X-JRC-Audio-Account'] = result.account_id
    headers['X-JRC-Audio-Unit'] = result.unit_id
    headers['X-JRC-Audio-Selection'] = result.selection_sha256
    headers['X-JRC-Audio-SHA256'] = result.sha256
    headers['X-JRC-Audio-Count'] = result.entry_count.to_s
    headers['X-JRC-Audio-Bytes'] = result.bytes.bytesize.to_s
  end
end
