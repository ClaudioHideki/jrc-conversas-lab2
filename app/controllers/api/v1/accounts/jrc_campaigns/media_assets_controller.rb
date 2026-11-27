class Api::V1::Accounts::JrcCampaigns::MediaAssetsController < Api::V1::Accounts::JrcCampaigns::BaseController
  include Rails.application.routes.url_helpers

  rescue_from ArgumentError, with: :invalid_media

  def create
    if params[:url].present?
      asset = JrcCampaigns::MetaMedia.import!(account: Current.account, user: Current.user, kind: params.require(:kind), url: params[:url])
    else
      asset = JrcCampaigns::MediaAsset.new(account: Current.account, created_by: Current.user, kind: params[:kind])
      uploaded = params.require(:file)
      JrcCampaigns::MetaMedia.validate_io!(uploaded.tempfile, params[:kind]) if ActiveModel::Type::Boolean.new.cast(params[:meta_template])
      asset.file.attach(uploaded)
      asset.save!
      JrcCampaigns::MetaMedia.validate!(asset) if ActiveModel::Type::Boolean.new.cast(params[:meta_template])
    end
    render json: {
      id: asset.id,
      url: rails_blob_url(asset.file, host: request.base_url),
      file_name: asset.file.filename.to_s,
      content_type: asset.file.content_type,
      byte_size: asset.file.byte_size
    }, status: :created
  end

  private

  def invalid_media(error)
    render json: { errors: [error.message] }, status: :unprocessable_entity
  end
end
