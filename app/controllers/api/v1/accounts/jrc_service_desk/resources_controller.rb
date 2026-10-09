# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::ResourcesController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  def index
    authorize ::JrcServiceDesk::OperationalResource, :index?
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[unit_id resource_kind state query page per_page])
    rows = filtered_resources(values)
    paging = ::JrcServiceDesk::QueryParameters.new(values.slice('page', 'per_page'))
    items = rows.order(updated_at: :desc, id: :desc).offset(paging.offset).limit(paging.per_page)
    render json: base_payload.merge(items: items.map { |row| resource_payload(row) },
                                    meta: { page: paging.page, per_page: paging.per_page, total: rows.count })
  end

  def show
    raise ArgumentError unless query_values.empty?

    row = scoped_resource
    authorize row, :show?
    render json: base_payload.merge(resource: resource_payload(row))
  end

  def create
    values = body_values(%w[unit_id resource])
    unit = ::JrcServiceDesk::OperationalContext.new(pundit_user).unit_scope.find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    authorize ::JrcServiceDesk::OperationalResource.new(account: Current.account, unit: unit), :create?
    row = command.create(unit_id: values.fetch('unit_id'), attributes: values.fetch('resource'),
                         idempotency_key: request.headers['Idempotency-Key'])
    render json: base_payload.merge(applied: true, resource: resource_payload(row)), status: :created
  end

  def update
    values = body_values(%w[unit_id resource expected_lock_version])
    authorize scoped_resource, :update?
    row = command.update(unit_id: values.fetch('unit_id'), resource_id: params[:resource_id],
                         attributes: values.fetch('resource'), expected_lock_version: values.fetch('expected_lock_version'))
    render json: base_payload.merge(applied: true, resource: resource_payload(row))
  end

  def destroy
    values = body_values(%w[unit_id expected_lock_version])
    authorize scoped_resource, :destroy?
    row = command.archive(unit_id: values.fetch('unit_id'), resource_id: params[:resource_id],
                          expected_lock_version: values.fetch('expected_lock_version'))
    render json: base_payload.merge(applied: true, resource: resource_payload(row))
  end

  def link_tickets
    values = body_values(%w[unit_id ticket_ids expected_lock_version])
    authorize scoped_resource, :update?
    row = command.update(unit_id: values.fetch('unit_id'), resource_id: params[:resource_id],
                         attributes: { ticket_ids: values.fetch('ticket_ids') }, expected_lock_version: values.fetch('expected_lock_version'))
    render json: base_payload.merge(applied: true, resource: resource_payload(row))
  end

  private

  def filtered_resources(values)
    rows = policy_scope(::JrcServiceDesk::OperationalResource)
    if values['unit_id']
      unit = policy_scope(::JrcServiceDesk::Unit).find(::JrcServiceDesk::Input.id(values['unit_id']))
      rows = rows.where(unit: unit)
    end
    %w[resource_kind state].each { |key| rows = rows.where(key => values[key]) if values[key] }
    search_resources(rows, values['query'])
  end

  def search_resources(rows, query)
    return rows unless query

    raise ArgumentError unless query.is_a?(String) && query.size <= 200

    term = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    rows.where('name ILIKE ? OR code ILIKE ?', term, term)
  end

  def command
    ::JrcServiceDesk::OperationalResourceService.new(user_context: pundit_user)
  end

  def scoped_resource
    policy_scope(::JrcServiceDesk::OperationalResource).find(::JrcServiceDesk::Input.id(params[:resource_id]))
  end

  def resource_payload(row)
    ::JrcServiceDesk::OperationalResourcePresenter.new(context: pundit_user).call(row)
  end
end
