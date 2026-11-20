# frozen_string_literal: true

# Technical history is authorized through the native library scope, never through client-shaped proof.
class Api::V1::Accounts::JrcContactCenter::AudioInspectionsController < Api::V1::Accounts::JrcContactCenter::BaseController
  wrap_parameters false

  before_action -> { response.headers['Cache-Control'] = 'no-store' }
  before_action -> { authorize_contact_center!(:configure?) }

  def index
    params[:page] = 1 if params[:page].blank?
    records = library.inspections(selected_version).includes(:created_by).order(attempt: :desc)
    render json: list_payload(records) { |row| JrcContactCenter::AudioLibraryPresenter.inspection(row) }
  end

  def create
    valid = (request.request_parameters.keys - ['idempotency_key']).empty?
    raise JrcContactCenter::OperationError, 'invalid_institutional_audio_inspection' unless valid

    record = JrcContactCenter::AudioInspections.new(access: library).create!(
      asset_id: params[:audio_asset_id], version_id: params[:version_id], key: params.require(:idempotency_key)
    )
    render json: base_payload.merge(item: JrcContactCenter::AudioLibraryPresenter.inspection(record)), status: :created
  end

  private

  def library
    @library ||= JrcContactCenter::AudioLibraryAccess.new(context: pundit_user)
  end

  def selected_version
    library.versions(library.asset(params[:audio_asset_id])).find(library.identifier!(params[:version_id]))
  end
end
