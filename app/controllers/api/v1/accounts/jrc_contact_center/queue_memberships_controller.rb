# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::QueueMembershipsController < Api::V1::Accounts::JrcContactCenter::BaseController
  def index
    authorize_contact_center!(:configure?)
    memberships = scoped_memberships.includes(:queue, account_user: :user).order(:queue_id, :priority, :id)
    memberships = memberships.where(queue_id: params[:queue_id]) if params[:queue_id].present?
    render json: base_payload.merge(items: memberships.map { |membership| serialize(membership) }, agents: agent_options)
  end

  def create
    authorize_contact_center!(:configure?)
    membership = JrcContactCenter::QueueMembership.create!(membership_params.merge(account: Current.account))
    render json: base_payload.merge(item: serialize(membership.reload)), status: :created
  end

  def update
    authorize_contact_center!(:configure?)
    membership = scoped_memberships.find(params[:id])
    membership.update!(membership_params)
    render json: base_payload.merge(item: serialize(membership.reload))
  end

  private

  def agent_options
    Current.account.account_users.includes(:user).order(:id).map do |member|
      { account_user_id: member.id.to_s, name: member.user.available_name }
    end
  end

  def scoped_memberships
    JrcContactCenter::QueueMembership.where(account: Current.account)
  end

  def membership_params
    permitted = params.require(:queue_membership).permit(:queue_id, :account_user_id, :role, :priority, :active,
                                                         :starts_at, :ends_at, settings: {})
    validate_scope!(permitted)
    permitted
  end

  def validate_scope!(attributes)
    JrcContactCenter::Queue.where(account: Current.account).find(attributes[:queue_id]) if attributes[:queue_id].present?
    Current.account.account_users.find(attributes[:account_user_id]) if attributes[:account_user_id].present?
  end

  def serialize(membership)
    user = membership.account_user.user
    membership.as_json(only: %i[id queue_id account_user_id role priority active starts_at ends_at settings created_at updated_at])
              .merge('queue_name' => membership.queue.name, 'user_id' => user.id, 'user_name' => user.name)
  end
end
