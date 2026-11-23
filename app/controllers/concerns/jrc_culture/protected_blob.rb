# frozen_string_literal: true

module JrcCulture::ProtectedBlob
  extend ActiveSupport::Concern

  included { prepend_before_action :deny_culture_blob }

  private

  def deny_culture_blob
    blob = @blob || culture_signed_blob || culture_disk_blob
    return unless blob&.metadata&.key?(JrcCulture::Files::MARKER)

    response.headers['Cache-Control'] = 'no-store'
    head :not_found
  end

  def culture_signed_blob
    id = params[:signed_blob_id] || params[:signed_id]
    ActiveStorage::Blob.find_signed(id) if id
  end

  def culture_disk_blob
    token = params[:encoded_key] || params[:encoded_token]
    return unless token

    purpose = params[:encoded_token] ? :blob_token : :blob_key
    key = ActiveStorage.verifier.verified(token, purpose: purpose)&.fetch(:key)
    return unless key

    ActiveStorage::Blob.find_by(key: key.start_with?('variants/') ? key.split('/')[1] : key)
  end
end
