# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::CallSessionsController < Api::V1::Accounts::JrcContactCenter::BaseController
  def index
    authorize_contact_center!
    calls = scoped_calls.order(started_at: :desc).limit(limit)
    calls = calls.where(status: params[:status]) if params[:status].present?
    render json: base_payload.merge(items: calls.map { |call| serialize(call) })
  end

  def show
    authorize_contact_center!
    call = contact_center_access.call_sessions.find(params[:id])
    render json: base_payload.merge(item: serialize(call, details: true).merge('journey' => journey(call)))
  end

  def observations
    authorize_contact_center!(:operate?)
    call = contact_center_access.call_sessions.find(params[:id])
    note = params.require(:observations).permit(:text, :lock_version)
    unless note[:text].is_a?(String) && note[:text].length <= 1000 && note[:lock_version].to_s.match?(/\A\d+\z/)
      render json: base_payload.merge(error: 'invalid_observations'), status: :unprocessable_entity
      return
    end

    call.with_lock do
      if call.lock_version != note[:lock_version].to_i
        raise JrcContactCenter::OperationError.new('stale_observations', status: :conflict)
      end
      call.update!(metadata: call.metadata.merge('attendance_observations' => {
                                                  'text' => note[:text], 'account_user_id' => Current.account_user.id,
                                                  'updated_at' => Time.current.iso8601
                                                }))
    end
    render json: base_payload.merge(item: serialize(call, details: true))
  end

  private

  def scoped_calls
    return contact_center_access.my_call_sessions unless contact_center_access.full_access?
    return contact_center_access.unassigned_call_sessions if params[:assignee_type] == 'unassigned'
    return contact_center_access.my_call_sessions if params[:assignee_type] == 'me'

    contact_center_access.call_sessions
  end

  def limit
    params.fetch(:limit, 50).to_i.clamp(1, 200)
  end

  def serialize(call, details: false)
    payload = call.as_json(only: %i[id provider external_session_id correlation_id direction status ani dnis contact_id company_id current_unit_id
                                   current_queue_id started_at answered_at ended_at lock_version])
                  .merge('metadata' => call.metadata.except('jrc_f1'))
    return payload unless details

    attendant = call.legs.where.not(account_user_id: nil).order(started_at: :desc, id: :desc).first&.account_user
    payload.merge('queue' => call.current_queue&.as_json(only: %i[id name]),
                  'attendant' => attendant && { id: attendant.id, name: attendant.user.name })
  end

  def journey(call)
    legs = call.legs.order(:started_at).map do |leg|
      leg.as_json(only: %i[id parent_leg_id queue_id account_user_id external_leg_id direction status started_at answered_at ended_at])
    end
    ivr = call.ivr_events.order(:occurred_at).map do |event|
      event.as_json(only: %i[id event_type menu_key option_key occurred_at])
    end
    { legs: legs, ivr: ivr }
  end
end
