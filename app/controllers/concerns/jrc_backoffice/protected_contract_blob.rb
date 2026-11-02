module JrcBackoffice::ProtectedContractBlob
  extend ActiveSupport::Concern
  included { prepend_before_action :deny_backoffice_contract_blob }

  private

  def deny_backoffice_contract_blob
    blob = @blob || signed_contract_blob || disk_contract_blob
    return unless blob && JrcBackoffice::PrivateBlob.protected?(blob.id)

    response.headers['Cache-Control'] = 'no-store'
    head :not_found
  end

  def signed_contract_blob
    signed_id = params[:signed_blob_id] || params[:signed_id]
    ActiveStorage::Blob.find_signed(signed_id) if signed_id
  end

  def disk_contract_blob
    encoded = params[:encoded_key] || params[:encoded_token]
    return unless encoded

    data = ActiveStorage.verifier.verified(encoded, purpose: params[:encoded_token] ? :blob_token : :blob_key)
    key = data&.fetch(:key)
    return unless key

    original_key = key.start_with?('variants/') ? key.split('/')[1] : key
    ActiveStorage::Blob.find_by(key: original_key)
  end
end
