# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::UnitCalendarsController < Api::V1::Accounts::JrcContactCenter::BaseController
  before_action :private_response

  def index
    data = catalog.call
    rows = selected_rows(data.fetch('entries'))
    page = page_number(:page, 1, 1_000_000)
    limit = page_number(:per_page, 20, 100)
    metadata = { page: page, per_page: limit, total: rows.length, pages: (rows.length.to_f / limit).ceil }
    render json: base_payload.merge(
      items: rows.slice((page - 1) * limit, limit) || [], meta: metadata,
      unit_id: data.fetch('unit_id'), unit_name: data.fetch('unit_name'), unit_timezone: data.fetch('unit_timezone'),
      revision: data.fetch('revision'), local_only: true, pabx_confirmed: false
    )
  end

  def show
    data = catalog.call
    item = data.fetch('entries').find { |row| row.fetch('id') == params[:id] } || raise(ActiveRecord::RecordNotFound)
    render json: base_payload.merge(
      item: item, unit_id: data.fetch('unit_id'), revision: data.fetch('revision'), local_only: true, pabx_confirmed: false
    )
  end

  def create
    result = writer.save!(document.fetch('calendar'), expected_revision: document.fetch('expected_revision'), create: true)
    render json: base_payload.merge(result), status: :created
  end

  def update
    row = document.fetch('calendar')
    valid = row.is_a?(Hash) && row['id'] == params[:id]
    raise JrcContactCenter::OperationError, 'invalid_contact_center_calendar_catalog' unless valid

    result = writer.save!(row, expected_revision: document.fetch('expected_revision'))
    render json: base_payload.merge(result)
  end

  def preview
    render json: base_payload.merge(preview: catalog.preview(params[:id], date: params[:date]))
  end

  private

  def private_response
    response.headers['Cache-Control'] = 'no-store'
    authorize_contact_center!(:configure?)
  end

  def catalog
    @catalog ||= JrcContactCenter::CalendarCatalog.new(context: pundit_user, unit_id: params[:unit_id])
  end

  def writer
    @writer ||= JrcContactCenter::CalendarCatalog.new(context: pundit_user, unit_id: document.fetch('unit_id'))
  end

  def document
    return @document if defined?(@document)

    valid = request.media_type == 'application/json' && request.raw_post.bytesize <= JrcContactCenter::CalendarCatalogState::MAX_BYTES
    raise JrcContactCenter::OperationError, 'invalid_contact_center_calendar_catalog' unless valid

    @document = ActiveSupport::JSON.decode(request.raw_post)
    valid = @document.is_a?(Hash) && @document.keys.sort == %w[calendar expected_revision unit_id]
    raise JrcContactCenter::OperationError, 'invalid_contact_center_calendar_catalog' unless valid

    @document
  end

  def selected_rows(rows)
    query, status = calendar_filters
    filtered = rows.select do |row|
      row.fetch('definition').fetch('name').downcase.include?(query) &&
        (status == 'all' || row.fetch('active') == (status == 'active'))
    end
    filtered.sort_by { |row| [row.fetch('definition').fetch('name').downcase, row.fetch('id')] }
  end

  def calendar_filters
    query = params.fetch(:q, '')
    status = params.fetch(:status, 'all')
    valid = query.is_a?(String) && query.length <= 100 && %w[all active inactive].include?(status)
    raise JrcContactCenter::OperationError, 'invalid_contact_center_calendar_filter' unless valid

    [query.strip.downcase, status]
  end

  def page_number(key, fallback, maximum)
    value = JrcServiceDesk::Input.id(params.fetch(key, fallback))
    raise JrcContactCenter::OperationError, 'invalid_contact_center_calendar_filter' if value > maximum

    value
  rescue ArgumentError
    raise JrcContactCenter::OperationError, 'invalid_contact_center_calendar_filter'
  end
end
