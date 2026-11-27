# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::RecordingTicketsController < Api::V1::Accounts::JrcContactCenter::BaseController
  before_action :private_response

  def index
    raise ArgumentError unless request.request_parameters.empty? && (request.query_parameters.keys - ['page']).empty?

    reader = JrcContactCenter::RecordingTicketList.new(account: Current.account, member: Current.account_user,
                                                       page: params.fetch(:page, 1))
    render json: reader.call(params[:recording_id])
  rescue ArgumentError
    render json: { error: 'invalid_recording_ticket_page' }, status: :unprocessable_entity
  end

  private

  def private_response
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Pragma'] = 'no-cache'
    response.headers['X-Content-Type-Options'] = 'nosniff'
  end
end
