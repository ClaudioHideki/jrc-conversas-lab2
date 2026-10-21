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
    render json: base_payload.merge(item: serialize(call).merge('journey' => journey(call)))
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

  def serialize(call)
    call.as_json(only: %i[id provider external_session_id correlation_id direction status ani dnis contact_id company_id current_unit_id
                          current_queue_id started_at answered_at ended_at lock_version]).merge('metadata' => call.metadata.except('jrc_f1'))
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
