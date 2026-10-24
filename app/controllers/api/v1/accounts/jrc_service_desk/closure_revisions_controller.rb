# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::ClosureRevisionsController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  rescue_from ::JrcServiceDesk::PublicationPreviewError, with: :invalid_preview
  before_action :authorize_administrative_revision!

  def versions
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[unit_id page])
    render json: base_payload.merge(service.versions(**values.symbolize_keys))
  end

  def proposal
    values = body_values(%w[unit_id source_version_id])
    render json: base_payload.merge(service.proposal(**values.symbolize_keys))
  end

  def index
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[unit_id source_version_id target_version_id page])
    render json: base_payload.merge(service.candidates(**values.symbolize_keys))
  end

  def preview
    values = body_values(%w[unit_id source_version_id target_version_id ticket_ids operational_review review_reason])
    render json: base_payload.merge(preview: service.preview(**values.symbolize_keys))
  end

  def create
    values = body_values(%w[unit_id receipt])
    render json: base_payload.merge(result: service.call(**values.symbolize_keys, idempotency_key: request.headers['Idempotency-Key'])), status: :created
  end

  def resume
    values = body_values(%w[unit_id idempotency_key])
    render json: base_payload.merge(result: service.resume(**values.symbolize_keys))
  end

  def result
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[unit_id idempotency_key])
    render json: base_payload.merge(result: service.readback(**values.symbolize_keys))
  end

  private

  def authorize_administrative_revision!
    values = request.get? ? query_values : request.request_parameters
    unit = ::JrcServiceDesk::OperationalContext.new(pundit_user).unit_scope.find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    policy_scope(::JrcServiceDesk::LifecyclePolicy).where(unit_id: unit.id)
    authorize ::JrcServiceDesk::LifecyclePolicy.new(account: Current.account, unit: unit), :publish?
  end

  def service
    ::JrcServiceDesk::ClosureRevisionService.new(user_context: pundit_user)
  end

  def invalid_preview
    render json: { code: 'preview_invalid', error: 'Atualize e revise a prévia antes de aplicar.' }, status: :conflict
  end
end
