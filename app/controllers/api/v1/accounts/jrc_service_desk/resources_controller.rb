# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::ResourcesController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  def index
    authorize ::JrcServiceDesk::OperationalResource, :index?
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[unit_id ticket_id resource_kind state query page per_page])
    rows = filtered_resources(values)
    paging = ::JrcServiceDesk::QueryParameters.new(values.slice('page', 'per_page'))
    items = rows.order(updated_at: :desc, id: :desc).offset(paging.offset).limit(paging.per_page)
    render json: base_payload.merge(items: items.map { |row| resource_payload(row) },
                                    summary: resource_summary(rows),
                                    meta: { page: paging.page, per_page: paging.per_page, total: rows.count })
  end

  def export
    context = ::JrcServiceDesk::OperationalContext.new(pundit_user)
    authorize ::JrcServiceDesk::OperationalResource, :index?
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[unit_id ticket_id resource_kind state query])
    rows = filtered_resources(values)
    raise ArgumentError, 'Export is limited to 10000 resources; narrow the filters' if rows.count > 10_000

    unit = policy_scope(::JrcServiceDesk::Unit).find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    data = rows.order(:id).map do |row|
      [row.id, row.name, row.code, row.details['serial'], row.details['manufacturer'], row.details['location'], row.state, row.priority]
    end
    content = ::JrcServiceDesk::OperationalCsv.generate(%w[id name code serial manufacturer location state priority], data)
    metadata = { namespace: 'jrc_sd_resource_export_v1', account_id: Current.account.id, unit_id: unit.id,
                 account_user_id: context.account_user.id, filters: values, count: data.size,
                 sha256: Digest::SHA256.hexdigest(content) }
    Audited::Audit.create!(auditable: unit, associated: unit, user: context.user, action: 'export', audited_changes: {},
                           comment: ::JrcServiceDesk::CanonicalJson.dump(metadata), request_uuid: SecureRandom.uuid)
    send_data "\uFEFF#{content}", filename: 'service-desk-resources.csv', type: 'text/csv; charset=utf-8', disposition: 'attachment'
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

  def unlink_ticket
    values = body_values(%w[unit_id expected_lock_version])
    authorize scoped_resource, :update?
    row = command.unlink(unit_id: values.fetch('unit_id'), resource_id: params[:resource_id], ticket_id: params[:ticket_id],
                         expected_lock_version: values.fetch('expected_lock_version'))
    render json: base_payload.merge(applied: true, resource: resource_payload(row))
  end

  private

  def resource_summary(rows)
    { total: rows.count, by_state: rows.group(:state).count }
  end

  def filtered_resources(values)
    rows = policy_scope(::JrcServiceDesk::OperationalResource)
    if values['unit_id']
      unit = policy_scope(::JrcServiceDesk::Unit).find(::JrcServiceDesk::Input.id(values['unit_id']))
      rows = rows.where(unit: unit)
    end
    if values['ticket_id']
      ticket = policy_scope(::JrcServiceDesk::Ticket).find(::JrcServiceDesk::Input.id(values['ticket_id']))
      authorize ticket, :show?
      rows = rows.where(id: ticket.operational_resource_links.active.select(:operational_resource_id))
    end
    %w[resource_kind state].each { |key| rows = rows.where(key => values[key]) if values[key] }
    search_resources(rows, values['query'])
  end

  def search_resources(rows, query)
    return rows unless query

    raise ArgumentError unless query.is_a?(String) && query.size <= 200

    term = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    rows.where("name ILIKE ? OR code ILIKE ? OR details->>'serial' ILIKE ? OR details->>'manufacturer' ILIKE ? OR details->>'location' ILIKE ?",
               term, term, term, term, term)
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
