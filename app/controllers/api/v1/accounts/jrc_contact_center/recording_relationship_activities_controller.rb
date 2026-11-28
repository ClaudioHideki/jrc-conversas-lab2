# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::RecordingRelationshipActivitiesController < Api::V1::Accounts::JrcContactCenter::BaseController
  before_action :private_response
  rescue_from ArgumentError, KeyError, ActionController::ParameterMissing, with: :invalid_request
  rescue_from ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, with: :concurrency_conflict

  def index
    reader = JrcContactCenter::RecordingRelationshipScope.new(account: Current.account, member: Current.account_user)
    render json: reader.preview(params[:recording_id], page: params.fetch(:page, 1))
  end

  def create
    writer = JrcContactCenter::RecordingRelationshipWrite.new(account: Current.account, member: Current.account_user)
    render json: base_payload.merge(writer.call(params[:recording_id], activity_input)), status: :created
  end

  private

  def private_response
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Pragma'] = 'no-cache'
    response.headers['X-Content-Type-Options'] = 'nosniff'
  end

  def invalid_request
    render json: base_payload.merge(error: 'invalid_recording_relationship_request'), status: :unprocessable_entity
  end

  def concurrency_conflict
    render json: base_payload.merge(error: 'recording_relationship_concurrency_conflict'), status: :conflict
  end

  def activity_input
    raise ArgumentError unless request.media_type == 'application/json' && request.raw_post.bytesize.between?(1, 65_536)

    input = params.require(:relationship_activity)
    raise ArgumentError unless input.is_a?(ActionController::Parameters)

    input.to_unsafe_h
  end
end
