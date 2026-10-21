class Api::V1::Accounts::JrcCampaigns::SanitizedListsController < Api::V1::Accounts::JrcCampaigns::BaseController
  before_action :set_list, only: [:show, :destroy]

  def index
    render json: Current.account.jrc_campaign_sanitized_lists.order(created_at: :desc).map { |list| serialize(list) }
  end

  def show
    render json: serialize(@list, include_entries: true)
  end

  def create
    list = JrcCampaigns::Sanitizer.new(
      account: Current.account,
      user: Current.user,
      name: params.require(:name),
      entries: normalized_entries
    ).perform
    render json: serialize(list, include_entries: true), status: :created
  end

  def destroy
    @list.destroy!
    head :no_content
  end

  private

  def set_list
    @list = Current.account.jrc_campaign_sanitized_lists.find(params[:id])
  end

  def normalized_entries
    Array(params[:entries]).map do |entry|
      entry.respond_to?(:permit) ? entry.permit!.to_h : entry
    end
  end

  def serialize(list, include_entries: false)
    payload = list.as_json(only: [:id, :name, :stats, :created_at])
    return payload unless include_entries

    payload.merge(entries: list.entries.order(:id).map do |entry|
      entry.as_json(only: [:id, :name, :phone_number, :normalized_phone, :email, :normalized_email, :status, :reason, :metadata])
    end)
  end
end
