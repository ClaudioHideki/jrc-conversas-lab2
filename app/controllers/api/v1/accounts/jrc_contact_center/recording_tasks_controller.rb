# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::RecordingTasksController < Api::V1::Accounts::JrcContactCenter::BaseController
  before_action :private_response

  def index
    reader = JrcContactCenter::RecordingTaskList.new(account: Current.account, member: Current.account_user, page: params.fetch(:page, 1))
    render json: base_payload.merge(reader.call(params[:recording_id]))
  end

  def create
    writer = JrcContactCenter::RecordingTaskWrite.new(account: Current.account, member: Current.account_user)
    row = writer.call(params[:recording_id], task_input)
    # Task content is obtained only by a subsequent, freshly authorized read.
    render json: base_payload.merge(recording_id: row.recording_id.to_s, link_id: row.id.to_s)
  end

  private

  def private_response
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Pragma'] = 'no-cache'
    response.headers['X-Content-Type-Options'] = 'nosniff'
  end

  def task_input
    unless request.media_type == 'application/json' && request.raw_post.bytesize.between?(1, 65_536)
      raise ArgumentError, 'Solicitação de tarefa inválida.'
    end

    params.require(:recording_task).to_unsafe_h
  end
end
