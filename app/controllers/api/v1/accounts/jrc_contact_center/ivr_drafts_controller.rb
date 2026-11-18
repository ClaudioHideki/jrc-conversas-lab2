# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::IvrDraftsController < Api::V1::Accounts::JrcContactCenter::BaseController
  before_action :authorize_drafts!

  def index
    result = JrcContactCenter::IvrDraftQuery.new(scope: draft_scope, params: params).call
    render json: base_payload.merge(items: result[:rows].map { |row| JrcContactCenter::IvrDraftPresentation.summary(row) }, meta: result[:meta])
  end

  def show
    draft = draft_scope.find!(params[:id])
    render json: base_payload.merge(item: present(draft, draft.latest_version))
  end

  def create
    write_draft
  end

  def update
    draft = draft_scope.find!(params[:id])
    unit = params.require(:ivr_draft)[:unit_id]
    if unit.present? && unit.to_s != draft.unit_id.to_s
      raise JrcContactCenter::OperationError, 'ivr_unit_is_immutable'
    end

    write_draft(id: draft.id)
  end

  def versions
    draft = draft_scope.find!(params[:id])
    relation = draft.versions.where(account: Current.account).order(revision: :desc)
    page = params.fetch(:page, '1')
    raise JrcContactCenter::OperationError, 'invalid_ivr_filter' unless page.is_a?(String) && page.match?(/\A[0-9]+\z/)

    page = page.to_i.clamp(1, 1_000_000)
    total = relation.count
    render json: base_payload.merge(items: relation.offset((page - 1) * 20).limit(20).map { |row| present(draft, row, include_definition: false) },
                                    meta: { page: page, per_page: 20, total: total, pages: (total.to_f / 20).ceil })
  end

  def version
    draft = draft_scope.find!(params[:id])
    render json: base_payload.merge(item: present(draft, selected_version(draft)))
  end

  def export
    draft = draft_scope.find!(params[:id])
    row = selected_version(draft)
    response.headers['X-JRC-IVR-Revision'] = row.revision.to_s
    send_data JSON.pretty_generate(row.definition), type: 'application/json',
                                                  filename: "ura-local-#{draft.id}-v#{row.revision}.json", disposition: 'attachment'
  end

  def preview
    request = params.require(:ivr_preview).permit(:unit_id, :dtmf, definition: {})
    graph = JrcContactCenter::IvrGraph.new(request[:definition].to_h, access: draft_scope.access, unit_id: request[:unit_id])
    result = JrcContactCenter::IvrSimulator.new(graph: graph).call(input: request[:dtmf])
    render json: base_payload.merge(simulation: result)
  end

  def simulate
    draft = draft_scope.find!(params[:id])
    request = params.require(:ivr_simulation).permit(:revision, :dtmf)
    row = selected_version(draft, request[:revision])
    graph = JrcContactCenter::IvrGraph.new(row.definition, access: draft_scope.access, unit_id: draft.unit_id)
    draft_scope.authorize_unchanged_scope!(draft, draft_scope.access.units.find(draft.unit_id))
    render json: base_payload.merge(simulation: JrcContactCenter::IvrSimulator.new(graph: graph).call(input: request[:dtmf]), revision: row.revision)
  end

  private

  def base_payload
    super.merge(timezone: Time.zone.tzinfo.identifier)
  end

  def authorize_drafts!
    response.headers['Cache-Control'] = 'no-store'
    authorize_contact_center!(:configure?)
  end

  def draft_scope
    @draft_scope ||= JrcContactCenter::IvrDraftAccess.new(context: pundit_user)
  end

  def selected_version(draft, revision = params[:revision])
    valid = revision.is_a?(Integer) && revision.positive?
    valid ||= revision.is_a?(String) && revision.match?(/\A[1-9][0-9]{0,9}\z/)
    raise ActiveRecord::RecordNotFound unless valid && revision.to_i <= 2_147_483_647

    draft.versions.where(account: Current.account).find_by!(revision: revision)
  end

  def write_draft(id: nil)
    request = params.require(:ivr_draft).permit(:unit_id, :name, :status, :request_id, :expected_revision, definition: {})
    unless request.key?(:expected_revision)
      raise JrcContactCenter::OperationError.new('ivr_revision_required', status: :precondition_required)
    end
    input = JrcContactCenter::IvrDraftInput.new(**request.except(:unit_id).to_h.symbolize_keys)
    result = JrcContactCenter::IvrDraftWrite.new(context: pundit_user).call(input: input, id: id, unit_id: request[:unit_id])
    render json: base_payload.merge(item: present(result[:draft], result[:version]), replayed: result[:replayed],
                                    latest_revision: result[:latest_revision]), status: (id || result[:replayed] ? :ok : :created)
  end

  def present(draft, row, include_definition: true)
    JrcContactCenter::IvrDraftPresentation.version(draft, row, include_definition: include_definition)
  end
end
