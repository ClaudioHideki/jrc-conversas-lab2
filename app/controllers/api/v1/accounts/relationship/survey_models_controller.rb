# frozen_string_literal: true

class Api::V1::Accounts::Relationship::SurveyModelsController < Api::V1::Accounts::Relationship::BaseController
  rescue_from JrcRelationship::SurveyModelContract::Invalid do |error|
    render json: { errors: error.details }, status: :unprocessable_entity
  end

  def index
    rows = editor.scope(params.require(:unit_id)).includes(:definition).order(updated_at: :desc, id: :desc)
    rows = rows.where(code: params[:code].to_s) if params[:code].present?
    # Pagination is applied after model ACL filtering, never leaks names/counts from other grants.
    permitted = rows.select { |row| editor.access.allowed?(row.published_payload.presence || row.payload, 'read') }
    number = params.fetch(:page, 1).to_i.clamp(1, 10_000)
    render json: { payload: permitted.slice((number - 1) * 20, 20).to_a.map { |row| editor.present(row) },
                   meta: { page: number, per_page: 20, total: permitted.size } }
  end

  def options
    render json: editor.options(params.require(:unit_id))
  end

  def show
    render json: editor.present(editor.find(params[:id]))
  end

  def create
    row = editor.save(payload: payload)
    render json: editor.present(row), status: :created
  end

  def update
    row = editor.save(id: params[:id], payload: payload, expected_version: params.require(:lock_version))
    render json: editor.present(row)
  end

  def validate
    row = editor.find(params[:id], action: 'publish')
    editor.validate_publication!(row.payload)
    render json: { valid: true, lock_version: row.lock_version }
  end

  def publish
    row = editor.publish(id: params[:id], expected_version: params.require(:lock_version), request_key: params.require(:request_key))
    render json: editor.present(row)
  end

  def duplicate
    render json: editor.present(editor.duplicate(id: params[:id])), status: :created
  end

  def deactivate
    row = editor.deactivate(id: params[:id], expected_version: params.require(:lock_version))
    render json: editor.present(row)
  end

  def evaluate_dispatch
    row = editor.find(params[:id], action: 'edit')
    raise Pundit::NotAuthorizedError unless relationship_context.policy.manage? && row.definition&.status == 'active'
    raise ArgumentError, 'Este modelo não permite envio manual.' unless row.published_payload.dig('rules', 'event') == 'manual'
    tickets = JrcServiceDesk::TicketPolicy::Scope.new(editor.access.operational.to_h, JrcServiceDesk::Ticket).resolve
    ticket = tickets.where(unit_id: row.unit_id).find(params.require(:ticket_id))
    reopening = ticket.lifecycle_transitions.where(action: 'reopen').order(:id).last
    rule = JrcRelationship::SurveyRule.where(account: Current.account, definition: row.definition).find_by!(active: true)
    result = JrcRelationship::SurveyEngine.evaluate_event(source: ticket, event: 'manual', rule_id: rule.id,
      cycle_key: "service-desk:ticket:#{ticket.id}:cycle:#{reopening&.id || 'initial'}")
    render json: { state: result.state, reason: result.reason, survey_id: result.survey_id }
  end

  def history
    row = editor.find(params[:id])
    rows = JrcRelationship::SurveyVersion.where(account: Current.account, entity_type: 'JrcRelationship::SurveyDefinition', entity_id: row.definition_id).order(version: :desc)
    render json: { payload: rows.limit(100) }
  end

  private

  def payload
    value = params.require(:payload)
    raise ArgumentError, 'Rascunho inválido.' unless value.respond_to?(:to_unsafe_h)
    # No mass assignment. The editor validates a bounded JSON contract and all scope references.
    value.to_unsafe_h.deep_stringify_keys
  end

  def editor
    @editor ||= JrcRelationship::SurveyModelEditor.new(relationship_context)
  end
end
