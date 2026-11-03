# A transaction participant, local to one newly allocated storage key. Rails
# promotes it from the item savepoint to the outer transaction on commit, so a
# later audit/caller rollback still compensates bytes after database rollback.
class JrcMigrations::StorageCompensation
  def initialize(blob:, item:, media: nil)
    @service = blob.service
    @reference = { 'service_name' => blob.service_name, 'blob_key' => blob.key.dup.freeze,
                   'sha256' => blob.metadata.fetch('migration_sha256') }.freeze
    @identity = { id: item.id, account_id: item.account_id, batch_id: item.batch_id }.freeze
    @media = media
    @media_id = media&.id
  end

  def register!
    ActiveRecord::Base.connection.add_transaction_record(self)
    self
  end

  def cleanup!
    return if @cleaned

    service = @media ? JrcMigrations::StorageIdentity.verify!(@media) : @service
    service.delete(@reference.fetch('blob_key'))
    @cleaned = true
  rescue StandardError
    raise JrcMigrations::Error.new('ATTACHMENT_CLEANUP_REQUIRED', private_context: @reference)
  end

  def trigger_transactional_callbacks? = false
  def before_committed!; end
  def committed!(**); end

  def rolledback!(**)
    media = JrcMigrations::MediaObject.find_by(id: @media_id, account_id: @identity[:account_id], item_id: @identity[:id])
    unless media
      persist_cleanup_reference!
      return
    end

    # Account -> Batch -> Item -> Media claim is committed before physical delete.
    # A retry either sees RECOVERING or its registered Blob is preserved as KEEP.
    JrcMigrations::MediaRecovery.compensate(media)
    persist_cleanup_reference! if media.reload.status == 'cleanup_required'
  rescue StandardError
    persist_cleanup_reference!
    connection = ActiveRecord::Base.connection
    connection.add_transaction_record(self) if connection.transaction_open?
  end

  private

  def persist_cleanup_reference!
    item = JrcMigrations::Item.find_by(@identity)
    return unless item

    item.with_lock do
      references = (Array(item.before_data['storage_cleanup']) + [@reference]).uniq
      item.update!(before_data: item.before_data.merge('storage_cleanup' => references))
    end
  end
end
