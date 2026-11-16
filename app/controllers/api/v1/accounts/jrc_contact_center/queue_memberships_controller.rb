# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::QueueMembershipsController < Api::V1::Accounts::JrcContactCenter::BaseController
  def index
    authorize_contact_center!(:configure?)
    memberships = scoped_memberships.includes(:queue, account_user: :user).order(:queue_id, :priority, :id)
    memberships = memberships.where(queue_id: params[:queue_id]) if params[:queue_id].present?
    if params[:q].present?
      memberships = memberships.joins(account_user: :user)
                               .where('users.name ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.first(100))}%")
    end
    memberships = memberships.where(active: params[:status] == 'active') if %w[active inactive].include?(params[:status])
    render json: list_payload(memberships) { |membership| serialize(membership) }.merge(agents: agent_options)
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
    eligible_members.includes(:user).order(:id).map do |member|
      { account_user_id: member.id.to_s, name: member.user.available_name }
    end
  end

  def eligible_members
    members = Current.account.account_users
    organizational = JrcContactCenter::OrganizationalScope.new(account: Current.account, account_user: Current.account_user)
    return members unless organizational.restricted?

    # A unit administrator may maintain assignments only for users already in
    # those queues. Account-wide enrollment is a distinct administrative scope.
    ids = scoped_memberships.select(:account_user_id)
    members.where(id: ids).or(members.where(id: Current.account_user.id))
  end

  def scoped_memberships
    JrcContactCenter::QueueMembership.where(account: Current.account, queue_id: contact_center_access.queues.select(:id))
  end

  def membership_params
    permitted = params.require(:queue_membership).permit(:queue_id, :account_user_id, :role, :priority, :active,
                                                         :starts_at, :ends_at, :participates, :supervises, settings: {})
    if permitted.key?(:participates) || permitted.key?(:supervises)
      participates = permitted.delete(:participates)
      supervises = permitted.delete(:supervises)
      raise JrcContactCenter::OperationError, 'invalid_membership_flags' unless [true, false].include?(participates) && [true, false].include?(supervises)
      raise JrcContactCenter::OperationError, 'membership_role_required' unless participates || supervises

      previous = action_name == 'update' ? scoped_memberships.find(params[:id]).settings : {}
      permitted[:role] = participates ? 'agent' : 'supervisor'
      permitted[:settings] = previous.merge(permitted[:settings]&.to_h || {}).merge('supervises' => supervises)
    end
    validate_scope!(permitted)
    permitted
  end

  def validate_scope!(attributes)
    contact_center_access.queues.find(attributes[:queue_id]) if attributes[:queue_id].present?
    eligible_members.find(attributes[:account_user_id]) if attributes[:account_user_id].present?
  end

  def serialize(membership)
    user = membership.account_user.user
    membership.as_json(only: %i[id queue_id account_user_id role priority active starts_at ends_at settings created_at updated_at])
              .merge('queue_name' => membership.queue.name, 'user_id' => user.id, 'user_name' => user.name,
                     'participates' => membership.role == 'agent', 'supervises' => membership.role == 'supervisor' || membership.settings['supervises'] == true)
  end
end
