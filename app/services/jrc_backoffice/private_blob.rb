# Classification only. A private file is read through an authorized domain
# endpoint; possession of an ActiveStorage locator never grants that access.
class JrcBackoffice::PrivateBlob
  DOCUMENT_TYPE = 'JrcBackoffice::DocumentVersion'.freeze

  def self.upload_owned(io:, filename:, content_type:, marker:)
    # Both APIs are public in the repository's pinned ActiveStorage version.
    # Keep the blob before storage I/O so a partial upload can be compensated.
    blob = ActiveStorage::Blob.create_after_unfurling!(io: io, filename: filename, content_type: content_type,
                                                       identify: false, metadata: { marker => true })
    blob.upload_without_unfurling(io)
    blob
  rescue StandardError
    clean_uncommitted(blob, marker: marker)
    raise
  end

  def self.contract?(id)
    JrcBackoffice::ContractVersion.exists?(pdf_blob_id: id)
  end

  def self.document?(id)
    JrcBackoffice::DocumentScan.exists?(source_blob_id: id) ||
      ActiveStorage::Attachment.exists?(blob_id: id, record_type: DOCUMENT_TYPE)
  end

  def self.protected?(id)
    contract?(id) || document?(id)
  end

  def self.clean_uncommitted(blob, marker:)
    return unless blob && blob.metadata[marker] == true
    return if uncached_reference?(blob.id)

    if ActiveStorage::Blob.uncached { ActiveStorage::Blob.exists?(id: blob.id) }
      blob.purge
    else
      # Rollback restores the native blob's new-record flag; purge would skip
      # its stored bytes. The absent blob row/FKs prevent a new committed owner.
      blob.service.delete(blob.key)
    end
  rescue StandardError => e
    # Uncertain database outcomes retain bytes; cleanup never replaces the
    # original failed action or logs filenames/content/storage locators.
    Rails.logger.warn("backoffice_owned_blob_cleanup_pending class=#{e.class.name}")
  end

  def self.uncached_reference?(id)
    ApplicationRecord.uncached { protected?(id) || ActiveStorage::Attachment.exists?(blob_id: id) }
  end
  private_class_method :uncached_reference?
end
