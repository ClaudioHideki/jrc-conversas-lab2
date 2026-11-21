# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::AudioAssetsController < Api::V1::Accounts::JrcContactCenter::BaseController
  # This API has an explicit typed asset body; do not add a second inferred audio_asset root.
  wrap_parameters false

  before_action -> { response.headers['Cache-Control'] = 'no-store' }
  before_action -> { authorize_contact_center!(:configure?) }

  def index
    params[:page] = 1 if params[:page].blank?
    unit = library.unit(params.require(:unit_id))
    records = library.assets.where(unit: unit)
    records = within_folder(records, unit)
    records = version_filtered(records)
    payload = list_payload(search_records(records, fields: ['name']).order(:name, :id)) { |row| present(row) }
    render json: payload.merge(max_upload_bytes: JrcContactCenter::AudioFileInput.max_bytes)
  end

  def show
    render json: base_payload.merge(item: present(library.asset(params[:id])))
  end

  def create
    validate_body!(%w[asset unit_id file idempotency_key source_kind])
    version = JrcContactCenter::AudioUploads.new(access: library).create!(
      unit_id: params.require(:unit_id), attributes: params.require(:asset), file: params.require(:file),
      key: params.require(:idempotency_key), source_kind: params.fetch(:source_kind, 'user_upload')
    )
    render json: base_payload.merge(item: present(library.asset(version.audio_asset_id)),
                                    received_version: JrcContactCenter::AudioLibraryPresenter.version(version)), status: :created
  end

  def duplicate
    validate_body!(%w[asset source_version_id expected_revision idempotency_key])
    version = JrcContactCenter::AudioCopies.new(access: library).call(
      asset_id: params[:id], version_id: params.require(:source_version_id), attributes: params.require(:asset),
      key: params.require(:idempotency_key), expected: params[:expected_revision]
    )
    render json: base_payload.merge(item: present(library.asset(version.audio_asset_id)),
                                    received_version: JrcContactCenter::AudioLibraryPresenter.version(version)), status: :created
  end

  def update
    validate_body!(%w[asset expected_revision])
    library.transaction do
      record = library.asset(params[:id])
      JrcContactCenter::AudioAssetRevision.check!(record, version: library.latest(record), expected: params[:expected_revision])
      record.update!(asset_attributes(record))
      render json: base_payload.merge(item: present(library.asset(record.id)))
    end
  end

  private

  def version_filtered(records)
    JrcContactCenter::AudioAssetFilters.new(records: records, source_kind: params[:source_kind], content_type: params[:content_type]).call
  end

  def library
    @library ||= JrcContactCenter::AudioLibraryAccess.new(context: pundit_user)
  end

  def within_folder(records, unit)
    return records unless params.key?(:folder_id)

    folder = library.folder(params[:folder_id], unit: unit)
    records.where(folder_id: folder&.id)
  end

  def asset_attributes(record)
    attributes = JrcContactCenter::AudioAssetAttributes.parse(params.require(:asset))
    if attributes.key?('folder_id')
      unit = library.unit(record.unit_id)
      attributes['folder_id'] = library.folder(attributes['folder_id'], unit: unit)&.id
    end
    attributes
  end

  def present(record)
    JrcContactCenter::AudioLibraryPresenter.asset(record)
  end

  def validate_body!(keys)
    valid = (request.request_parameters.keys - keys).empty?
    raise JrcContactCenter::OperationError, 'invalid_institutional_audio' unless valid
  end
end
