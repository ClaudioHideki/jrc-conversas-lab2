# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::QueueMembershipsController < Api::V1::Accounts::JrcContactCenter::BaseController
  def index
    authorize_contact_center!(:configure?)
    memberships = filtered_memberships
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

  def filtered_memberships
    memberships = scoped_memberships.includes(:queue, account_user: :user).order(:queue_id, :priority, :id)
    memberships = memberships.where(queue_id: params[:queue_id]) if params[:queue_id].present?
    if params[:q].present?
      query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.first(100))}%"
      memberships = memberships.joins(account_user: :user).where('users.name ILIKE ?', query)
    end
    memberships = memberships.where(active: params[:status] == 'active') if %w[active inactive].include?(params[:status])
    memberships
  end

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
    apply_membership_flags!(permitted) if permitted.key?(:participates) || permitted.key?(:supervises)
    validate_scope!(permitted)
    permitted
  end

  def apply_membership_flags!(permitted)
    participates = permitted.delete(:participates)
    supervises = permitted.delete(:supervises)
    unless [true, false].include?(participates) && [true, false].include?(supervises)
      raise JrcContactCenter::OperationError, 'invalid_membership_flags'
    end
    raise JrcContactCenter::OperationError, 'membership_role_required' unless participates || supervises

    permitted[:role] = participates ? 'agent' : 'supervisor'
    permitted[:settings] = previous_settings.merge(permitted[:settings].to_h).merge('supervises' => supervises)
  end

  def previous_settings
    action_name == 'update' ? scoped_memberships.find(params[:id]).settings : {}
  end

  def validate_scope!(attributes)
    queue = contact_center_access.queues.find(attributes[:queue_id]) if attributes[:queue_id].present?
    eligible_members.find(attributes[:account_user_id]) if attributes[:account_user_id].present?
    validate_queue_enrollment!(attributes, queue)
  end

  def validate_queue_enrollment!(attributes, queue)
    membership = scoped_memberships.find(params[:id]) if action_name == 'update'
    queue ||= membership&.queue
    return if queue.nil? || queue.status == 'active'

    raise JrcContactCenter::OperationError, 'inactive_queue' if new_enrollment?(attributes, membership)
  end

  def new_enrollment?(attributes, membership)
    return true unless membership

    changed_target = attributes.slice(:queue_id, :account_user_id).to_h.any? do |key, value|
      value.to_s != membership.public_send(key).to_s
    end
    activate = attributes.key?(:active) && ActiveModel::Type::Boolean.new.cast(attributes[:active]) && !membership.active?
    changed_target || activate
  end

  def serialize(membership)
    user = membership.account_user.user
    membership.as_json(only: %i[id queue_id account_user_id role priority active starts_at ends_at settings created_at updated_at])
              .merge('queue_name' => membership.queue.name, 'user_id' => user.id, 'user_name' => user.name,
                     'participates' => membership.role == 'agent',
                     'supervises' => membership.role == 'supervisor' || membership.settings['supervises'] == true)
  end
end
