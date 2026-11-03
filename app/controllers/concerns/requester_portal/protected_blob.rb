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

    accesses = protected_blob_accesses(blob)
    return if accesses.empty?

    response.headers['Cache-Control'] = 'no-store'
    return head :not_found unless accesses.all?(&:allowed?)

    send_protected_blob(blob, accesses)
  rescue JrcServiceDesk::AttachmentScanError, ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError
    head :not_found
  end

  def send_protected_blob(blob, accesses)
    # Do not redirect to an object-storage bearer URL after authorizing. Each
    # subsequent download must pass this same current-session check.
    imported = accesses.find { |access| access.is_a?(JrcMigrations::ProtectedBlobAccess) }
    bytes = imported ? imported.download : blob.download
    send_data bytes, filename: blob.filename.to_s, type: blob.content_type, disposition: 'attachment'
  end

  def protected_blob_accesses(blob)
    context = { blob: blob, user: current_user, grant_id: requester_credentials['grant_id'] }
    [JrcServiceDesk::ProtectedBlobAccess.new(**context), JrcMigrations::ProtectedBlobAccess.new(**context)].select(&:protected?)
  end

  def service_desk_disk_blob
    return unless params[:encoded_key]

    key = ActiveStorage.verifier.verified(params[:encoded_key], purpose: :blob_key)&.fetch(:key)
    return unless key

    key = key.split('/')[1] if key.start_with?('variants/')
    ActiveStorage::Blob.find_by(key: key)
  end
end
