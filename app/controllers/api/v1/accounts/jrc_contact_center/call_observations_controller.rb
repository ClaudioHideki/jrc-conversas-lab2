# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::CallObservationsController < Api::V1::Accounts::JrcContactCenter::BaseController
  def index
    authorize_contact_center!(:operate?)
    call = contact_center_access.call_sessions.find(params[:id])
    items = observations(call).limit(page_size + 1).to_a
    more = items.length > page_size
    items = items.first(page_size)
    render json: base_payload.merge(call_session_id: call.id, items: items.as_json(only: %i[id author_user_id call_version text created_at]),
                                    next_before_id: more ? items.last.id : nil)
  end

  private

  def page_size
    params.fetch(:limit, 50).to_i.clamp(1, 100)
  end

  def observations(call)
    records = JrcContactCenter::CallObservation.where(account_id: Current.account.id, call_session: call).order(id: :desc)
    params[:before_id].present? ? records.where('id < ?', params[:before_id].to_i) : records
  end
end
