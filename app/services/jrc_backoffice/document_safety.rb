require 'digest'

# Reuses the native local scanner. Callers still authorize the request/actor;
# a clean malware observation grants neither document approval nor powers.
class JrcBackoffice::DocumentSafety
  class NotClean < StandardError; end

  def initialize(version)
    @version = version
  end

  def scan!
    @version.with_lock('FOR NO KEY UPDATE') do
      ensure_origin!
      previous = current
      next previous if previous&.clean?

      blob = @version.file.blob
      result = JrcServiceDesk::AttachmentScanner.new.scan(blob, socket_path: ENV.fetch('JRC_BO_CLAMAV_SOCKET', nil))
      ensure_origin!
      raise ActiveStorage::IntegrityError unless @version.file.reload.blob.id == blob.id

      store!(blob, result)
    end
  end

  def current
    row = JrcBackoffice::DocumentScan.where(account_id: @version.account_id, document_version_id: @version.id).order(attempt: :desc).first
    return unless row && @version.file.attached? && row.source_blob_id == @version.file.blob.id && row.expected_sha256 == @version.sha256

    row
  end

  def bytes!
    ensure_origin!
    scan = current
    raise NotClean unless scan&.clean?

    blob = @version.file.blob
    bytes = blob.download
    raise ActiveStorage::IntegrityError unless Digest::SHA256.hexdigest(bytes) == scan.observed_sha256

    ensure_origin!
    raise ActiveStorage::IntegrityError unless @version.file.reload.blob.id == blob.id && current&.id == scan.id

    bytes
  end

  private

  def ensure_origin!
    account = @version.account.reload
    request = @version.backoffice_request.reload
    raise Pundit::NotAuthorizedError unless account.active? && account.feature_enabled?('jrc_crm') && request.account_id == account.id
    raise ActiveStorage::IntegrityError unless @version.file.attached?
  end

  def store!(blob, result)
    observed = result['service_desk_scan_sha256']
    state = result['service_desk_scan_state']
    state = 'unavailable' unless %w[clean infected].include?(state) && observed.to_s.match?(/\A[a-f0-9]{64}\z/)
    state = 'checksum_mismatch' if observed && observed != @version.sha256
    rows = JrcBackoffice::DocumentScan.where(account_id: @version.account_id, document_version_id: @version.id)
    rows.create!(account: @version.account, document_version: @version, source_blob: blob, attempt: rows.maximum(:attempt).to_i + 1,
                 state: state, expected_sha256: @version.sha256, observed_sha256: observed, scanner_adapter: 'clamav-instream-v1',
                 failure_code: state == 'clean' ? nil : state.upcase)
  end
end
