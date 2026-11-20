# frozen_string_literal: true

# Same native ActiveStorage extension points as private company/Backoffice documents.
module JrcContactCenter::ProtectedAudioBlob
  extend ActiveSupport::Concern

  included do
    prepend_before_action :deny_institutional_audio_blob
  end

  private

  def deny_institutional_audio_blob
    blob = @blob
    signed_id = params[:signed_blob_id] || params[:signed_id]
    blob ||= ActiveStorage::Blob.find_signed(signed_id) if signed_id
    blob ||= institutional_disk_blob
    return unless blob && JrcContactCenter::PrivateAudioBlob.protected?(blob)

    # No account role or signed locator bypasses the dedicated authorized bytes API.
    response.headers['Cache-Control'] = 'no-store'
    head :not_found
  end

  def institutional_disk_blob
    encoded = params[:encoded_key] || params[:encoded_token]
    return unless encoded

    data = ActiveStorage.verifier.verified(encoded, purpose: params[:encoded_token] ? :blob_token : :blob_key)
    return unless data.is_a?(Hash)

    key = data[:key] || data['key']
    return unless key.is_a?(String)

    key = key.split('/')[1] if key.start_with?('variants/')
    ActiveStorage::Blob.find_by(key: key)
  end
end
