# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::QueuesController < Api::V1::Accounts::JrcContactCenter::BaseController
  def index
    authorize_contact_center!
    queues = contact_center_access.queues.includes(:unit).order(:name)
    render json: base_payload.merge(items: queues.map { |queue| serialize(queue) })
  end

  def create
    authorize_contact_center!(:configure?)
    queue = JrcContactCenter::Queue.create!(queue_params.merge(account: Current.account))
    render json: base_payload.merge(item: serialize(queue)), status: :created
  end

  def update
    authorize_contact_center!(:configure?)
    queue = JrcContactCenter::Queue.where(account: Current.account).find(params[:id])
    queue.update!(queue_params)
    render json: base_payload.merge(item: serialize(queue))
  end

  private

  def queue_params
    permitted = params.require(:queue).permit(:unit_id, :code, :name, :external_ref, :service_kind, :strategy, :status,
                                              :max_wait_seconds, :active_from, :active_until, settings: {})
    JrcContactCenter::Unit.where(account: Current.account).find(permitted[:unit_id]) if permitted[:unit_id].present?
    permitted
  end

  def serialize(queue)
    queue.as_json(only: %i[id unit_id code name external_ref service_kind strategy status max_wait_seconds active_from active_until settings])
         .merge('unit_name' => queue.unit.name)
  end
end
