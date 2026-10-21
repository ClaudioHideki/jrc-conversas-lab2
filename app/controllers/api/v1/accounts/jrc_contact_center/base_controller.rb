# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_contact_center_enabled!
  around_action :use_account_timezone

  rescue_from JrcContactCenter::Providers::BaseAdapter::CapabilityUnavailable, with: :render_capability_unavailable
  rescue_from JrcContactCenter::OperationError, with: :render_operation_error

  private

  def ensure_contact_center_enabled!
    raise Pundit::NotAuthorizedError unless Current.account&.active? && Current.account.feature_enabled?('jrc_contact_center')

    @contact_center_account_id = Current.account.id
  end

  def authorize_contact_center!(action = :access?)
    authorize :contact_center, action, policy_class: JrcContactCenter::ModulePolicy
  end

  def use_account_timezone(&)
    timezone = Time.find_zone(Current.account.reporting_timezone) || Time.zone
    Time.use_zone(timezone, &)
  end

  def base_payload
    { contract_version: 1, account_id: @contact_center_account_id.to_s }
  end

  def contact_center_access
    @contact_center_access ||= JrcContactCenter::AccessScope.new(user_context: pundit_user)
  end

  def ensure_contact_center_assignment!(queue_id: nil, owner_account_user_id: nil, require_accessible_assignment: false)
    return if contact_center_access.full_access?

    queue_allowed = accessible_queue?(queue_id)
    owner_allowed = own_assignment?(owner_account_user_id)
    reject_inaccessible_assignment!(queue_id, queue_allowed)
    reject_inaccessible_assignment!(owner_account_user_id, owner_allowed)
    raise Pundit::NotAuthorizedError if require_accessible_assignment && !queue_allowed && !owner_allowed
  end

  def reject_inaccessible_assignment!(assignment_id, allowed)
    raise Pundit::NotAuthorizedError if assignment_id.present? && !allowed
  end

  def accessible_queue?(queue_id)
    queue_id.present? && contact_center_access.queue_ids.include?(queue_id.to_i)
  end

  def own_assignment?(owner_account_user_id)
    owner_account_user_id.present? && owner_account_user_id.to_i == Current.account_user.id
  end

  def render_capability_unavailable(error)
    render json: base_payload.merge(error: 'provider_capability_unavailable', message: error.message), status: :not_implemented
  end

  def render_operation_error(error)
    render json: base_payload.merge(error: error.code), status: error.status
  end
end
