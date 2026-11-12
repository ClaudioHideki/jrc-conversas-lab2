module JrcCustomers::ProtectedImportBlob
  extend ActiveSupport::Concern
  included { prepend_before_action :deny_customer_import_blob }

  private

  def deny_customer_import_blob
    blob = @blob || signed_import_blob || disk_import_blob
    return unless blob && JrcCustomers::ImportBlob.protected?(blob)

    response.headers['Cache-Control'] = 'no-store'
    head :not_found
  end

  def signed_import_blob
    signed_id = params[:signed_blob_id] || params[:signed_id]
    ActiveStorage::Blob.find_signed(signed_id) if signed_id
  end

  def disk_import_blob
    encoded = params[:encoded_key] || params[:encoded_token]
    return unless encoded

    data = ActiveStorage.verifier.verified(encoded, purpose: params[:encoded_token] ? :blob_token : :blob_key)
    key = data&.fetch(:key)
    return unless key

    ActiveStorage::Blob.find_by(key: key.start_with?('variants/') ? key.split('/')[1] : key)
  end
end
