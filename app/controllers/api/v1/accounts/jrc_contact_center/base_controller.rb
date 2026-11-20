# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_contact_center_enabled!
  around_action :use_account_timezone
  around_action :use_configuration_audit_context

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

  def use_configuration_audit_context
    previous = Audited.store[:current_request_uuid]
    Audited.store[:current_request_uuid] = request.request_id
    yield
  ensure
    Audited.store[:current_request_uuid] = previous
  end

  def base_payload
    { contract_version: 1, account_id: @contact_center_account_id.to_s }
  end

  # The same Account mutex used by eligibility, profiles and corporate sources.
  # Each request builds fresh native scopes after waiting, before any write.
  def with_current_operating_authority
    JrcContactCenter::AuthorityTransaction.call(account: Current.account, member: Current.account_user) do
      Current.user.reload
      raise Pundit::NotAuthorizedError unless Current.user.active_for_authentication?

      @contact_center_access = JrcContactCenter::AccessScope.new(user_context: pundit_user)
      authorize_contact_center!(:operate?)
      yield
    end
  end

  def authorize_operating_origins!(attributes)
    contact_center_access.units.find(attributes[:unit_id]) if attributes[:unit_id].present?
    contact_center_access.cases.find(attributes[:case_id]) if attributes[:case_id].present?
    contact_center_access.call_sessions.find(attributes[:call_session_id]) if attributes[:call_session_id].present?
  end

  def attach_operating_call_origin!(attributes, case_record: false)
    call = authorize_operating_origins!(attributes)
    return attributes unless call

    attributes[:queue_id] = call.current_queue_id unless attributes.key?(:queue_id)
    attributes[:unit_id] = call.current_unit_id if case_record && !attributes.key?(:unit_id)
    attributes
  end

  def configuration_revision_options
    params.key?(:expected_revision) ? { expected_revision: params[:expected_revision] } : {}
  end

  def configuration_write
    @configuration_write ||= JrcContactCenter::ConfigurationWrite.new(
      account: Current.account, access: contact_center_access, reauthorize: method(:reauthorize_configuration_write!)
    )
  end

  def reauthorize_configuration_write!(record)
    Current.account.reload
    Current.account_user.reload
    Current.user.reload
    raise Pundit::NotAuthorizedError unless Current.user.active_for_authentication?

    @contact_center_access = JrcContactCenter::AccessScope.new(user_context: pundit_user)
    raise Pundit::NotAuthorizedError unless @contact_center_access.policy.configure?

    configuration_scope(record).find(record.id) if record&.persisted?
    @contact_center_access
  end

  def configuration_scope(record)
    case record
    when JrcContactCenter::Unit then contact_center_access.units
    when JrcContactCenter::Queue then contact_center_access.queues
    when JrcContactCenter::QueueMembership
      JrcContactCenter::QueueMembership.where(account: Current.account, queue_id: contact_center_access.queues.select(:id))
    else
      raise ActiveRecord::RecordNotFound
    end
  end

  def contact_center_access
    @contact_center_access ||= JrcContactCenter::AccessScope.new(user_context: pundit_user)
  end

  def list_payload(relation, &)
    page = params.fetch(:page, 1).to_i.clamp(1, 1_000_000)
    per_page = params.fetch(:per_page, 20).to_i.clamp(1, 100)
    total = relation.count
    rows = params.key?(:page) ? relation.offset((page - 1) * per_page).limit(per_page) : relation
    base_payload.merge(items: rows.map(&),
                       meta: { page: page, per_page: per_page, total: total, pages: (total.to_f / per_page).ceil })
  end

  def search_records(relation, fields: %w[name code])
    query = params[:q].to_s.strip.first(100)
    if query.present?
      relation = relation.where(fields.map { |field| "#{field} ILIKE :query" }.join(' OR '),
                                query: "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
    end
    if %w[active inactive].include?(params[:status]) && relation.klass.column_names.include?('status')
      relation = relation.where(status: params[:status])
    end
    relation
  end

  def ensure_contact_center_assignment!(queue_id: nil, owner_account_user_id: nil, require_accessible_assignment: false)
    validate_queue_assignment!(queue_id)
    Current.account.account_users.find(owner_account_user_id) if owner_account_user_id.present?
    return if contact_center_access.full_access?

    queue_allowed = accessible_queue?(queue_id)
    owner_allowed = own_assignment?(owner_account_user_id)
    reject_inaccessible_assignment!(queue_id, queue_allowed)
    reject_inaccessible_assignment!(owner_account_user_id, owner_allowed)
    raise Pundit::NotAuthorizedError if require_accessible_assignment && !queue_allowed && !owner_allowed
  end

  def validate_queue_assignment!(queue_id)
    raise Pundit::NotAuthorizedError if queue_id.present? && !contact_center_access.queues.exists?(id: queue_id)
  end

  def reject_inaccessible_assignment!(assignment_id, allowed)
    raise Pundit::NotAuthorizedError if assignment_id.present? && !allowed
  end

  def accessible_queue?(queue_id)
    queue_id.present? && contact_center_access.queues.exists?(id: queue_id)
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
