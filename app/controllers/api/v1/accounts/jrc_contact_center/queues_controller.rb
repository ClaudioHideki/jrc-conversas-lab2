# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::QueuesController < Api::V1::Accounts::JrcContactCenter::BaseController
  def index
    authorize_contact_center!
    queues = search_records(contact_center_access.queues).includes(:unit).order(:name, :id)
    queues = queues.where(unit_id: params[:unit_id]) if params[:unit_id].present?
    render json: list_payload(queues) { |queue| serialize(queue) }
  end

  def create
    authorize_contact_center!(:configure?)
    queue = configuration_write.create!(JrcContactCenter::Queue) { queue_params }
    render json: base_payload.merge(item: serialize(queue)), status: :created
  end

  def update
    authorize_contact_center!(:configure?)
    queue = configuration_write.update!(contact_center_access.queues, params[:id]) { queue_params }
    render json: base_payload.merge(item: serialize(queue))
  end

  private

  def queue_params
    permitted = params.require(:queue).permit(:unit_id, :code, :name, :external_ref, :service_kind, :strategy, :status,
                                              :max_wait_seconds, :active_from, :active_until, settings: {})
    contact_center_access.units.find(permitted[:unit_id]) if permitted[:unit_id].present?
    permitted
  end

  def serialize(queue)
    queue.as_json(only: %i[id unit_id code name external_ref service_kind strategy status max_wait_seconds active_from active_until settings])
         .merge('unit_name' => queue.unit.name)
  end
end
