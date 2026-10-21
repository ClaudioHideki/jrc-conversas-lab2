# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::CallbacksController < Api::V1::Accounts::JrcContactCenter::BaseController
  def index
    authorize_contact_center!
    callbacks = scoped_callbacks.order(scheduled_at: :asc).limit(200)
    callbacks = callbacks.where(state: params[:state]) if params[:state].present?
    render json: base_payload.merge(items: callbacks.map { |record| serialize(record) })
  end

  def create
    authorize_contact_center!(:operate?)
    attributes = callback_params
    ensure_contact_center_assignment!(queue_id: attributes[:queue_id], owner_account_user_id: attributes[:owner_account_user_id],
                                      require_accessible_assignment: true)
    callback = JrcContactCenter::Callback.create!(attributes.merge(account: Current.account))
    render json: base_payload.merge(item: serialize(callback)), status: :created
  end

  def update
    authorize_contact_center!(:operate?)
    callback = scoped_callbacks.find(params[:id])
    attributes = callback_params
    effective_queue = attributes.key?(:queue_id) ? attributes[:queue_id] : callback.queue_id
    effective_owner = attributes.key?(:owner_account_user_id) ? attributes[:owner_account_user_id] : callback.owner_account_user_id
    ensure_contact_center_assignment!(queue_id: effective_queue, owner_account_user_id: effective_owner, require_accessible_assignment: true)
    callback.update!(attributes)
    render json: base_payload.merge(item: serialize(callback))
  end

  private

  def scoped_callbacks
    contact_center_access.callbacks
  end

  def callback_params
    params.require(:callback).permit(:call_session_id, :case_id, :contact_id, :queue_id, :owner_account_user_id, :target_phone,
                                     :consent_channel, :idempotency_key, :state, :attempts, :scheduled_at, :completed_at, metadata: {})
  end

  def serialize(record)
    record.as_json(only: %i[id call_session_id case_id contact_id queue_id owner_account_user_id target_phone consent_channel idempotency_key state
                            attempts scheduled_at completed_at metadata created_at updated_at])
  end
end
