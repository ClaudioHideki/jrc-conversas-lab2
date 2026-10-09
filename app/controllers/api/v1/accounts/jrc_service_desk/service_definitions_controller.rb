# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::ServiceDefinitionsController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  def index
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[unit_id page])
    unit = policy_scope(::JrcServiceDesk::Unit).find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    authorize ::JrcServiceDesk::Service.new(account: Current.account, unit: unit), :show?
    page = ::JrcServiceDesk::Input.id(values.fetch('page', 1))
    render json: base_payload.merge(service_page(unit, page))
  end

  def show
    raise ArgumentError unless query_values.empty?

    row = policy_scope(::JrcServiceDesk::Service).find(::JrcServiceDesk::Input.id(params[:id]))
    authorize row, :show?
    render json: base_payload.merge(service: project(row))
  end

  def create
    values = body_values(%w[unit_id service])
    unit = policy_scope(::JrcServiceDesk::Unit).find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    authorize ::JrcServiceDesk::Service.new(account: Current.account, unit: unit), :create?
    row = ::JrcServiceDesk::CreateServiceDefinitionService.new(user_context: pundit_user).call(unit_id: unit.id, attributes: values.fetch('service'),
                                                                                               idempotency_key: request.headers['Idempotency-Key'])
    render json: base_payload.merge(service: project(row)), status: :created
  end

  private

  def service_page(unit, page)
    scope = policy_scope(::JrcServiceDesk::Service).where(unit_id: unit.id, active: true).order(:name, :id)
    { unit_id: unit.id.to_s, items: scope.offset((page - 1) * 20).limit(20).map { |row| project(row) },
      meta: { page: page, per_page: 20, total: scope.count } }
  end

  def project(row)
    projection = ::JrcServiceDesk::ConfigurationResources.project('services', row)
    projection.each { |key, value| projection[key] = value.to_s if key.end_with?('_id') && value }
    projection
  end
end
