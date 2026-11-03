class JrcMigrations::MediaPlan
  def self.reserve!(item:, prepared:)
    previous = scope(item).lock.order(:generation).last
    return verify!(previous, prepared) if previous&.status.in?(%w[reserved verifying verification_required planned])
    raise JrcMigrations::Error, 'MEDIA_RECOVERY_REQUIRED' if previous && !previous.status.in?(%w[cleaned kept])

    create_reservation!(item, prepared, previous)
  end

  def self.create_reservation!(item, prepared, previous)
    JrcMigrations::MediaObject.create!(account_id: item.account_id, batch_id: item.batch_id, item: item,
                                       generation: (previous&.generation || 0) + 1, service_name: ActiveStorage::Blob.service.name,
                                       storage_key: SecureRandom.base36(28), source_sha256: prepared.payload.sha256,
                                       byte_size: prepared.payload.bytes.bytesize,
                                       storage_identity: JrcMigrations::StorageIdentity.fingerprint(ActiveStorage::Blob.service))
  end

  def self.for_write!(item:, prepared:)
    raise JrcMigrations::Error, 'MEDIA_PREVIEW_REQUIRED' unless item

    media = scope(item).lock.order(:generation).last
    JrcMigrations::StorageIdentity.verify!(media) if media
    raise JrcMigrations::Error, 'MEDIA_PREVIEW_REQUIRED' unless media&.status == 'planned'
    raise JrcMigrations::Error, 'MEDIA_PREVIEW_REQUIRED' unless media.absence_verified_at

    verify!(media, prepared)
  end

  def self.scope(item)
    JrcMigrations::MediaObject.where(account_id: item.account_id, batch_id: item.batch_id, item_id: item.id)
  end

  def self.verify!(media, prepared)
    unless media.source_sha256 == prepared.payload.sha256 && media.byte_size == prepared.payload.bytes.bytesize
      raise JrcMigrations::Error, 'MEDIA_SOURCE_CHANGED'
    end

    media
  end
  private_class_method :scope, :verify!, :create_reservation!
end
