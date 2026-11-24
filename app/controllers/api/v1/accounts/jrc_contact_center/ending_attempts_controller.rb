# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::EndingAttemptsController < Api::V1::Accounts::JrcContactCenter::BaseController
  def index
    response.headers['Cache-Control'] = 'no-store'
    service = JrcContactCenter::EndingActions::AttemptHistory.new(
      account: Current.account, member: Current.account_user,
      qualification_id: qualification_identity, page: params.fetch(:page, 1)
    )
    render json: base_payload.merge(service.call)
  end

  private

  def qualification_identity
    JrcServiceDesk::Input.id(params[:qualification_id])
  rescue ArgumentError
    raise JrcContactCenter::OperationError, 'invalid_ending_history_request'
  end
end
