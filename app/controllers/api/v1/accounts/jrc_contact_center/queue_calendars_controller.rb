# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::QueueCalendarsController < Api::V1::Accounts::JrcContactCenter::BaseController
  before_action :private_configuration

  def index
    validate_filters!
    relation = search_records(service.targets(params[:calendar_id], binding_filter: params.fetch(:binding_filter, 'all'))).order(:name, :id)
    data = list_payload(relation) { |queue| service.show(queue.id) }
    render json: data.merge(unit_id: params[:unit_id].to_s, local_only: true, pabx_confirmed: false, external_impact: 'unknown')
  end

  def show
    render json: base_payload.merge(service.show(params[:id]))
  end

  def update
    raise JrcContactCenter::OperationError, 'invalid_queue_calendar_binding' unless document['queue_id'] == params[:id]

    result = JrcContactCenter::QueueCalendars.new(context: pundit_user, unit_id: document.fetch('unit_id')).save!(document)
    render json: base_payload.merge(result)
  end

  def destroy
    raise JrcContactCenter::OperationError, 'invalid_queue_calendar_removal' unless document['queue_id'] == params[:id]

    result = JrcContactCenter::QueueCalendarRemovals.new(context: pundit_user, unit_id: document['unit_id']).call(document)
    render json: base_payload.merge(result)
  end

  private

  def validate_filters!
    params[:page] = page_number(:page, 1, 1_000_000)
    params[:per_page] = page_number(:per_page, 20, 100)
    query = params.fetch(:q, '')
    valid = query.is_a?(String) && query.length <= 100
    raise JrcContactCenter::OperationError, 'invalid_queue_calendar_binding' unless valid
  end

  def page_number(key, fallback, maximum)
    value = JrcServiceDesk::Input.id(params.fetch(key, fallback))
    raise JrcContactCenter::OperationError, 'invalid_queue_calendar_binding' if value > maximum

    value
  rescue ArgumentError
    raise JrcContactCenter::OperationError, 'invalid_queue_calendar_binding'
  end

  def private_configuration
    response.headers['Cache-Control'] = 'no-store'
    authorize_contact_center!(:configure?)
  end

  def service
    @service ||= JrcContactCenter::QueueCalendars.new(context: pundit_user, unit_id: params[:unit_id])
  end

  def document
    return @document if defined?(@document)

    valid = request.media_type == 'application/json' && request.raw_post.bytesize <= 4096
    raise JrcContactCenter::OperationError, 'invalid_queue_calendar_binding' unless valid

    @document = ActiveSupport::JSON.decode(request.raw_post)
    raise JrcContactCenter::OperationError, 'invalid_queue_calendar_binding' unless @document.is_a?(Hash)

    @document
  end
end
