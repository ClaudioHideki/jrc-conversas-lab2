class JrcRelationship::DocumentScanJob < ApplicationJob
  queue_as :default

  def perform(version_id)
    version = JrcRelationship::DocumentVersion.find_by(id: version_id)
    return unless version&.file&.attached?

    blob = version.file.blob
    result = JrcServiceDesk::AttachmentScanner.new.scan(blob)
    blob.with_lock { blob.update!(metadata: blob.metadata.merge(result)) }
  end
end
