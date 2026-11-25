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

  def execute_pending
    response.headers['Cache-Control'] = 'no-store'
    command = JrcContactCenter::EndingActions::RunPendingProjectAttempt.new(
      account: Current.account, member: Current.account_user, qualification_id: qualification_identity,
      attempt_id: attempt_identity, review: pending_review
    )
    render json: base_payload.merge(command.call)
  end

  private

  def attempt_identity
    JrcServiceDesk::Input.id(params[:attempt_id])
  rescue ArgumentError
    raise JrcContactCenter::OperationError, 'invalid_ending_pending_review'
  end

  def pending_review
    raw = request.raw_post
    unless request.media_type == 'application/json' && raw.bytesize.between?(1, 4096)
      raise JrcContactCenter::OperationError, 'invalid_ending_pending_review'
    end

    ActiveSupport::JSON.decode(raw)
  rescue JSON::ParserError
    raise JrcContactCenter::OperationError, 'invalid_ending_pending_review'
  end

  def qualification_identity
    JrcServiceDesk::Input.id(params[:qualification_id])
  rescue ArgumentError
    raise JrcContactCenter::OperationError, 'invalid_ending_history_request'
  end
end
