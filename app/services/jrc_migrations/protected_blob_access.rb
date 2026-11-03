# Provenance marks a blob as protected; only its surviving typed, mapped source
# and the current native project permission can authorize a download.
class JrcMigrations::ProtectedBlobAccess
  DOMAINS = { 'JrcProjects::Project' => 'project_attachments', 'JrcProjects::Task' => 'project_task_attachments' }.freeze
  private_constant :DOMAINS

  def initialize(blob:, user:, grant_id: nil, account_id: nil)
    @blob = blob
    @user = user
    @grant_id = grant_id
    @account_id = account_id
  end

  def protected?
    @blob.metadata.keys.any? { |key| key.start_with?('migration_') } || origins.any?
  end

  def allowed?
    return false if @grant_id.present? || !@user&.active_for_authentication?
    return false unless JrcServiceDesk::AttachmentScanner.clean?(@blob) && origins.any?

    origins.all? { |origin| authorized_origin?(origin) }
  end

  def download
    raise JrcServiceDesk::AttachmentScanError unless allowed?

    bytes = JrcServiceDesk::AttachmentScanner.download(@blob)
    actual = Digest::SHA256.hexdigest(bytes)
    raise JrcServiceDesk::AttachmentScanError unless origins.all? { |origin| source_digest(origin) == actual }

    bytes
  end

  private

  def origins
    @origins ||= @blob.attachments.includes(:record).flat_map do |attachment|
      domain = DOMAINS[attachment.record_type]
      record = attachment.record
      next [] unless domain && record && attachment.name == 'attachments'

      JrcMigrations::Mapping.where(account_id: record.account_id, domain: domain, target_id: attachment.id).map do |mapping|
        { attachment: attachment, record: record, mapping: mapping }
      end
    end
  end

  def authorized_origin?(origin)
    record = origin.fetch(:record)
    project = record.is_a?(JrcProjects::Task) ? record.project : record
    return false if @account_id && project.account_id != @account_id
    return false unless project.account_id == record.account_id && source_digest(origin).present?
    return false unless source_digest(origin) == @blob.metadata['service_desk_scan_sha256']

    member = AccountUser.find_by(account_id: project.account_id, user_id: @user.id)
    capability = record.is_a?(JrcProjects::Task) ? 'projects.task.view' : 'projects.project.view'
    JrcProjects::Authorization.allowed?(account_user: member, capability: capability, project: project, record: record)
  end

  def source_digest(origin)
    mapping = origin.fetch(:mapping)
    item = JrcMigrations::Item.find_by(account_id: mapping.account_id, batch_id: mapping.batch_id, legacy_id: mapping.legacy_id,
                                       target_id: origin.fetch(:attachment).id, status: %w[applied ignored])
    digest = item&.normalized_data&.fetch('file_sha256', nil)
    digest if digest.is_a?(String) && /\A[a-f0-9]{64}\z/.match?(digest)
  end
end
