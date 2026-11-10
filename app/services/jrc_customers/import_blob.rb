require 'stringio'

# CSVs may contain personal data. Their storage locator is never an access grant.
class JrcCustomers::ImportBlob
  MARKER = 'jrc_customer_import'.freeze

  def self.protected?(blob)
    return true if blob.metadata.key?(MARKER)

    attachments = ActiveStorage::Attachment.where(blob_id: blob.id, record_type: 'DataImport')
    attachments.joins('INNER JOIN data_imports ON data_imports.id = active_storage_attachments.record_id')
               .exists?(data_imports: { data_type: 'customer_master' })
  end

  def self.upload!(run:, content:)
    blob = ActiveStorage::Blob.create_after_unfurling!(io: StringIO.new(content), filename: 'customer-import.csv', content_type: 'text/csv',
                                                       identify: false, metadata: { MARKER => run.id })
    raise JrcCustomers::ImportFile::InvalidFile, 'Import storage must be private' if blob.service.public?

    blob.upload_without_unfurling(StringIO.new(content))
    run.import_file.attach(blob)
    blob
  rescue StandardError
    clean_uncommitted(blob)
    raise
  end

  def self.read!(run:)
    blob = run.import_file.blob
    raise JrcCustomers::ImportFile::InvalidFile, 'Import file is unavailable' unless blob && blob.metadata[MARKER] == run.id
    raise JrcCustomers::ImportFile::InvalidFile, 'Import file exceeds 1 MiB' if blob.byte_size > JrcCustomers::CompanyImport::MAX_BYTES

    content = blob.download
    return content if Digest::SHA256.hexdigest(content) == run.source_metadata.fetch('sha256')

    raise JrcCustomers::ImportFile::InvalidFile, 'Import file changed; upload it again'
  end

  def self.clean_uncommitted(blob)
    return unless blob
    return if ActiveStorage::Attachment.uncached { ActiveStorage::Attachment.exists?(blob_id: blob.id) }

    if ActiveStorage::Blob.uncached { ActiveStorage::Blob.exists?(id: blob.id) }
      blob.purge
    else
      blob.service.delete(blob.key)
    end
  rescue StandardError => e
    Rails.logger.warn("customer_import_cleanup_pending class=#{e.class.name}")
  end
end
