# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::AcwFormsController < Api::V1::Accounts::JrcContactCenter::BaseController
  before_action :authorize_forms!

  def index
    result = JrcContactCenter::AcwFormQuery.new(scope: form_scope, params: params).call
    render json: base_payload.merge(items: result[:rows].map { |row| JrcContactCenter::AcwFormPresentation.summary(row) }, meta: result[:meta])
  end

  def show
    form = form_scope.find!(params[:id])
    render json: base_payload.merge(item: present(form, form.latest_version))
  end

  def create
    write_form
  end

  def update
    write_form(id: form_scope.find!(params[:id]).id)
  end

  def versions
    form = form_scope.find!(params[:id])
    page = history_page
    relation = form.versions.where(account: Current.account).order(revision: :desc)
    total = relation.count
    items = relation.offset((page - 1) * 20).limit(20).map { |row| present(form, row, include_definition: false) }
    render json: base_payload.merge(items: items, meta: { page: page, per_page: 20, total: total, pages: (total.to_f / 20).ceil })
  end

  def version
    form = form_scope.find!(params[:id])
    revision = params[:revision]
    valid = revision.is_a?(String) && revision.match?(/\A[1-9][0-9]{0,9}\z/) && revision.to_i <= 2_147_483_647
    raise ActiveRecord::RecordNotFound unless valid

    row = form.versions.where(account: Current.account).find_by!(revision: revision)
    render json: base_payload.merge(item: present(form, row))
  end

  private

  def authorize_forms!
    response.headers['Cache-Control'] = 'no-store'
    authorize_contact_center!(:configure?)
    form_scope
  end

  def form_scope
    @form_scope ||= JrcContactCenter::AcwFormAccess.new(context: pundit_user)
  end

  def base_payload
    super.merge(timezone: Time.zone.tzinfo.identifier)
  end

  def history_page
    page = params.fetch(:page, '1')
    valid = page.is_a?(String) && page.match?(/\A[0-9]{1,9}\z/)
    raise JrcContactCenter::OperationError, 'invalid_acw_form_filter' unless valid

    page.to_i.clamp(1, 1_000_000)
  end

  def write_form(id: nil)
    result = JrcContactCenter::AcwFormWrite.new(context: pundit_user).call(input: form_input, id: id)
    render json: base_payload.merge(item: present(result[:form], result[:version]), replayed: result[:replayed],
                                    latest_revision: result[:latest_revision]), status: (id || result[:replayed] ? :ok : :created)
  end

  def form_input
    request = params.require(:acw_form)
    keys = %w[name description status request_id expected_revision definition]
    valid = request.is_a?(ActionController::Parameters) && (request.keys - keys).empty?
    raise JrcContactCenter::OperationError, 'invalid_acw_form_revision' unless valid
    raise JrcContactCenter::OperationError.new('acw_form_revision_required', status: :precondition_required) unless request.key?(:expected_revision)

    attributes = request.permit(:name, :description, :status, :request_id, :expected_revision, definition: {}).to_h.symbolize_keys
    JrcContactCenter::AcwFormInput.new(**attributes)
  end

  def present(form, row, include_definition: true)
    JrcContactCenter::AcwFormPresentation.version(form, row, include_definition: include_definition)
  end
end
