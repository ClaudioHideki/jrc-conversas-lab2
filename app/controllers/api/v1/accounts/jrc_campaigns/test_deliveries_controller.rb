class Api::V1::Accounts::JrcCampaigns::TestDeliveriesController < Api::V1::Accounts::JrcCampaigns::BaseController
  def index
    render json: scope.order(id: :desc).limit(50).map { |delivery| serialize(delivery) }
  end

  def show
    render json: serialize(scope.find(params[:id]))
  end

  private

  def scope
    JrcCampaigns::TestDelivery.where(account: Current.account)
  end

  def serialize(delivery)
    delivery.as_json(only: [:id, :inbox_id, :phone_number, :external_id, :status, :error_message, :error_code, :accepted_at, :sent_at, :delivered_at, :read_at, :failed_at, :requested_by_id, :created_at]).merge(
      provider_status: delivery.metadata['provider_status'], template: delivery.metadata['template'], language: delivery.metadata['language'], message_id: delivery.metadata['message_id'],
      delivery_confirmed: delivery.metadata['provider_status'].in?(%w[delivered read])
    )
  end
end
