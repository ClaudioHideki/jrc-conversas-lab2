# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::RecordingCustomerLinksController < Api::V1::Accounts::JrcContactCenter::BaseController
  before_action :private_response
  rescue_from Pabx::Error, with: :source_unavailable

  def show
    render json: writer.preview(params[:recording_id])
  end

  def create
    input = params.require(:customer_link).permit(:contact_id, :call_session_id, :call_id, :lock_version, :confirm).to_h
    render json: writer.call(params[:recording_id], input)
  rescue ArgumentError, KeyError
    render json: { error: 'invalid_recording_contact_link' }, status: :unprocessable_entity
  rescue ActiveRecord::StatementInvalid
    render json: { error: 'recording_contact_link_persistence_failed' }, status: :service_unavailable
  end

  private

  def writer
    JrcContactCenter::RecordingCustomerLink.new(account: Current.account, member: Current.account_user)
  end

  def source_unavailable
    render json: { error: 'recording_contact_link_source_unavailable' }, status: :service_unavailable
  end

  def private_response
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Pragma'] = 'no-cache'
    response.headers['X-Content-Type-Options'] = 'nosniff'
  end
end
