# frozen_string_literal: true

# Version history and private admission only. There is deliberately no byte-release action here.
class Api::V1::Accounts::JrcContactCenter::AudioVersionsController < Api::V1::Accounts::JrcContactCenter::BaseController
  before_action -> { response.headers['Cache-Control'] = 'no-store' }
  before_action -> { authorize_contact_center!(:configure?) }

  def index
    params[:page] = 1 if params[:page].blank?
    asset = library.asset(params[:audio_asset_id])
    render json: list_payload(library.versions(asset).includes(:created_by).order(number: :desc)) { |row| present(row) }
  end

  def create
    keys = %w[file idempotency_key expected_revision]
    raise JrcContactCenter::OperationError, 'invalid_institutional_audio' unless (request.request_parameters.keys - keys).empty?

    version = JrcContactCenter::AudioUploads.new(access: library).replace!(
      asset_id: params[:audio_asset_id], file: params.require(:file), key: params.require(:idempotency_key), expected: params[:expected_revision]
    )
    render json: base_payload.merge(item: JrcContactCenter::AudioLibraryPresenter.asset(library.asset(version.audio_asset_id)),
                                   received_version: present(version)), status: :created
  end

  private

  def library
    @library ||= JrcContactCenter::AudioLibraryAccess.new(context: pundit_user)
  end

  def present(record)
    JrcContactCenter::AudioLibraryPresenter.version(record)
  end
end
