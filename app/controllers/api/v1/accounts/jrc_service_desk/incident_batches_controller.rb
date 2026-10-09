# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::IncidentBatchesController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  rescue_from ::JrcServiceDesk::PublicationPreviewError, with: :invalid_preview

  def suggestions
    authorize ::JrcServiceDesk::Incident, :index?
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[unit_id])
    unit = context.unit_scope.find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    render json: base_payload.merge(unit_id: unit.id.to_s, recurrence: ::JrcServiceDesk::RecurrenceProjection.new(context: context, unit: unit).call)
  end

  def preview
    values = body_values(%w[unit_id batch])
    authorize_incident!(values)
    result = service.preview(unit_id: values.fetch('unit_id'), incident_id: params[:incident_id], attributes: values.fetch('batch'))
    render json: base_payload.merge(unit_id: values['unit_id'].to_s, preview: result)
  end

  def create
    values = body_values(%w[unit_id batch receipt note_receipts])
    authorize_incident!(values)
    result = service.call(unit_id: values.fetch('unit_id'), incident_id: params[:incident_id], attributes: values.fetch('batch'),
                          idempotency_key: request.headers['Idempotency-Key'], receipt: values.fetch('receipt'),
                          note_receipts: values.fetch('note_receipts', {}))
    render json: base_payload.merge(unit_id: values['unit_id'].to_s, applied: true, result: result), status: :created
  end

  def result
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[unit_id idempotency_key])
    unit = context.unit_scope.find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    incident = policy_scope(::JrcServiceDesk::Incident).where(unit_id: unit.id).find(::JrcServiceDesk::Input.id(params[:incident_id]))
    authorize incident, :show?
    result = service.readback(unit_id: unit.id, incident_id: incident.id, idempotency_key: values.fetch('idempotency_key'))
    render json: base_payload.merge(unit_id: unit.id.to_s, result: result)
  end

  private

  def context
    @context ||= ::JrcServiceDesk::OperationalContext.new(pundit_user)
  end

  def service
    ::JrcServiceDesk::IncidentBatchService.new(user_context: pundit_user)
  end

  def authorize_incident!(values)
    incident = policy_scope(::JrcServiceDesk::Incident).where(unit_id: ::JrcServiceDesk::Input.id(values.fetch('unit_id')))
                                                       .find(::JrcServiceDesk::Input.id(params[:incident_id]))
    authorize incident, :update?
  end

  def invalid_preview
    render json: { code: 'preview_invalid', error: 'Refresh and review the batch again' }, status: :conflict
  end
end
