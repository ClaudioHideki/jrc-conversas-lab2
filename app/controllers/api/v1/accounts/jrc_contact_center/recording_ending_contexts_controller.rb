# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::RecordingEndingContextsController < Api::V1::Accounts::JrcContactCenter::BaseController
  def show
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Pragma'] = 'no-cache'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    reader = JrcContactCenter::QualityReviewSource.new(account: Current.account, member: Current.account_user, action: :recordings_listen)
    reader.with_record(params[:recording_id]) do |record, call|
      service = JrcContactCenter::RecordingEndingContext.new(account: Current.account, member: Current.account_user,
                                                            call: call, page: params.fetch(:page, 1))
      render json: base_payload.merge(service.call).merge(recording_id: record.id.to_s, call_id: record.external_unique_id)
    end
  end
end
