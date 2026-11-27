# frozen_string_literal: true

# Read-only native intake context. This preview is not a grant or a write receipt.
class Api::V1::Accounts::JrcContactCenter::RecordingTicketIntakesController < Api::V1::Accounts::JrcContactCenter::BaseController
  def show
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Pragma'] = 'no-cache'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    reader = JrcContactCenter::RecordingTicketIntake.new(account: Current.account, member: Current.account_user)
    render json: reader.preview(params[:recording_id])
  rescue ArgumentError, JrcServiceDesk::IdempotencyConflict
    render json: { error: 'recording_ticket_intake_mapping_unavailable' }, status: :unprocessable_entity
  end
end
