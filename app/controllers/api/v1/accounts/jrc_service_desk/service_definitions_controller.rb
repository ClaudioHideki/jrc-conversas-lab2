# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::ServiceDefinitionsController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  def index
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[unit_id page])
    unit = policy_scope(::JrcServiceDesk::Unit).find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    authorize ::JrcServiceDesk::Service.new(account: Current.account, unit: unit), :show?
    page = ::JrcServiceDesk::Input.id(values.fetch('page', 1))
    scope = policy_scope(::JrcServiceDesk::Service).where(unit_id: unit.id, active: true).order(:name, :id)
    render json: base_payload.merge(unit_id: unit.id.to_s, items: scope.offset((page - 1) * 20).limit(20).map { |r| project(r) },
      meta: { page: page, per_page: 20, total: scope.count })
  end

  def create
    values = body_values(%w[unit_id service])
    unit = policy_scope(::JrcServiceDesk::Unit).find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    authorize ::JrcServiceDesk::Service.new(account: Current.account, unit: unit), :create?
    row = ::JrcServiceDesk::CreateServiceDefinitionService.new(user_context: pundit_user).call(unit_id: unit.id, attributes: values.fetch('service'), idempotency_key: request.headers['Idempotency-Key'])
    render json: base_payload.merge(service: project(row)), status: :created
  end

  def show
    raise ArgumentError unless query_values.empty?
    row = policy_scope(::JrcServiceDesk::Service).find(::JrcServiceDesk::Input.id(params[:id]))
    authorize row, :show?
    render json: base_payload.merge(service: project(row))
  end

  private

  def project(row)
    { id: row.id.to_s, account_id: row.account_id.to_s, unit_id: row.unit_id.to_s, name: row.name, code: row.code, active: row.active }
  end
end
