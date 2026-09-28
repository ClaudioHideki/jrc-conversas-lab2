# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::LifecyclePoliciesController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  def index
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[unit_id page])
    unit = policy_scope(::JrcServiceDesk::Unit).find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    candidate = ::JrcServiceDesk::LifecyclePolicy.new(account: Current.account, unit: unit)
    authorize candidate, :publish?
    page = ::JrcServiceDesk::Input.id(values.fetch('page', 1))
    scope = ::JrcServiceDesk::LifecyclePolicy.where(account_id: Current.account.id, unit_id: unit.id).order(:id)
    render json: base_payload.merge(unit_id: unit.id.to_s, items: scope.offset((page - 1) * 20).limit(20).map { |p| project(p) },
      meta: { page: page, per_page: 20, total: scope.count })
  end

  def show
    raise ArgumentError unless query_values.empty?
    record = policy_scope(::JrcServiceDesk::LifecyclePolicy).find(::JrcServiceDesk::Input.id(params[:id]))
    authorize record, :show?
    render json: base_payload.merge(policy: project(record))
  end

  def create
    values = body_values(%w[unit_id policy])
    unit = policy_scope(::JrcServiceDesk::Unit).find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    authorize ::JrcServiceDesk::LifecyclePolicy.new(account: Current.account, unit: unit), :publish?
    result = ::JrcServiceDesk::PublishLifecyclePolicyService.new(user_context: pundit_user).call(unit_id: unit.id, attributes: values.fetch('policy'))
    render json: base_payload.merge(policy: project(result)), status: :created
  end

  private

  def project(record)
    authorize record, :show?
    version = record.current_version
    { id: record.id.to_s, account_id: record.account_id.to_s, unit_id: record.unit_id.to_s, service_id: record.service_id&.to_s,
      name: record.name, enabled: record.enabled, version_id: version&.id&.to_s, version: version&.version || 0,
      digest: version&.digest, definition: version&.definition }
  end
end
