module JrcRelationship::ProtectedDocumentBlob
  extend ActiveSupport::Concern
  included do
    prepend_before_action :deny_relationship_document_blob
  end

  private

  def deny_relationship_document_blob
    blob = @blob
    signed_id = params[:signed_blob_id] || params[:signed_id]
    blob ||= ActiveStorage::Blob.find_signed(signed_id) if signed_id
    blob ||= relationship_disk_blob
    return unless blob&.attachments&.exists?(record_type: JrcRelationship::DocumentVersion.polymorphic_name)

    # These files must always pass the scoped Relationship API, including a fresh
    # user permission check, malware/hash validation and a download audit.
    response.headers['Cache-Control'] = 'no-store'
    head :not_found
  end

  def relationship_disk_blob
    encoded = params[:encoded_key] || params[:encoded_token]
    return unless encoded

    data = ActiveStorage.verifier.verified(encoded, purpose: params[:encoded_token] ? :blob_token : :blob_key)
    key = data&.fetch(:key)
    return unless key

    key = key.split('/')[1] if key.start_with?('variants/')
    ActiveStorage::Blob.find_by(key: key)
  end
end
