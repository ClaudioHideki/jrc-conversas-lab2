# frozen_string_literal: true

module RequesterPortal::ProtectedBlob
  extend ActiveSupport::Concern
  include DeviseTokenAuth::Concerns::SetUserByToken
  include RequesterPortal::NativeSession

  included do
    before_action :authorize_service_desk_blob
  end

  private

  def authorize_service_desk_blob
    blob = @blob || service_desk_disk_blob
    return unless blob

    access = JrcServiceDesk::ProtectedBlobAccess.new(blob: blob, user: current_user, grant_id: requester_credentials['grant_id'])
    return unless access.protected?

    response.headers['Cache-Control'] = 'no-store'
    return head :not_found unless access.allowed?

    # Do not redirect to an object-storage bearer URL after authorizing. Each
    # subsequent download must pass this same current-session check.
    send_data blob.download, filename: blob.filename.to_s, type: blob.content_type, disposition: 'attachment'
  end

  def service_desk_disk_blob
    return unless params[:encoded_key]

    key = ActiveStorage.verifier.verified(params[:encoded_key], purpose: :blob_key)&.fetch(:key)
    return unless key

    key = key.split('/')[1] if key.start_with?('variants/')
    ActiveStorage::Blob.find_by(key: key)
  end
end
