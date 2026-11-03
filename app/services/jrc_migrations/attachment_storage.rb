require 'stringio'

class JrcMigrations::AttachmentStorage
  def self.sha256(blob)
    blob.open { |file| Digest::SHA256.file(file.path).hexdigest }
  rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError, IOError, SystemCallError
    raise JrcMigrations::Error, 'ATTACHMENT_STORAGE_UNVERIFIED'
  end

  def self.cleanup!(blob)
    blob.service.delete(blob.key) if blob&.persisted?
  rescue StandardError
    context = { 'service_name' => blob.service_name, 'blob_key' => blob.key, 'sha256' => blob.metadata['migration_sha256'] }
    raise JrcMigrations::Error.new('ATTACHMENT_CLEANUP_REQUIRED', private_context: context)
  end

  def initialize(account:, source:, prepared:, item: nil)
    @account = account
    @source = source
    @prepared = prepared
    @item = item
  end

  def call
    @media = JrcMigrations::MediaPlan.for_write!(item: @item, prepared: @prepared)
    @prepared.parent.reload.with_lock do
      raise JrcMigrations::Error, 'RELATION_OUTSIDE_ACCOUNT' unless @prepared.parent.account_id == @account.id
      raise JrcMigrations::Error, 'INVALID_DESTINATION' unless @prepared.parent.valid?

      create_blob!
      raise JrcMigrations::Error, 'ATTACHMENT_STORAGE_UNVERIFIED' unless self.class.sha256(@blob) == @prepared.payload.sha256

      attach!
    end
  rescue StandardError => e
    cleanup!
    raise e if e.is_a?(JrcMigrations::Error)

    raise JrcMigrations::Error, 'ATTACHMENT_STORAGE_UNVERIFIED'
  end

  private

  def create_blob!
    payload = @prepared.payload
    @blob = ActiveStorage::Blob.create_before_direct_upload!(
      key: @media.storage_key, service_name: @media.service_name,
      filename: payload.filename, byte_size: payload.bytes.bytesize, checksum: Digest::MD5.base64digest(payload.bytes),
      content_type: payload.content_type, metadata: payload.metadata(account_id: @account.id, source: @source)
    )
    @compensation = JrcMigrations::StorageCompensation.new(blob: @blob, item: @item, media: @media).register!
    @blob.upload(StringIO.new(payload.bytes), identify: false)
  end

  # The typed parent and actual attachment model are validated; no parent touch,
  # analyzer, previewer or attachment callbacks may run for imported history.
  # rubocop:disable Rails/SkipsModelValidations
  def attach!
    attachment = ActiveStorage::Attachment.new(name: 'attachments', record: @prepared.parent, blob: @blob, created_at: @prepared.created_at)
    raise JrcMigrations::Error, 'INVALID_DESTINATION' unless attachment.valid?

    attributes = attachment.attributes.except('id')
    id = ActiveStorage::Attachment.insert_all!([attributes], returning: %w[id]).rows.first.first
    @media.update!(status: 'attached', blob: @blob, checked_at: Time.current, error_code: nil)
    ActiveStorage::Attachment.find(id).tap { |record| record.association(:blob).target = @blob }
  end
  # rubocop:enable Rails/SkipsModelValidations

  def cleanup!
    @compensation ? @compensation.cleanup! : self.class.cleanup!(@blob)
  end
end
