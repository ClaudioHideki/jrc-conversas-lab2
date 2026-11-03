class JrcMigrations::StorageIdentity
  def self.fingerprint(service)
    identity = case service.class.name
               when 'ActiveStorage::Service::DiskService'
                 path = File.expand_path(service.root.to_s)
                 { adapter: 'Disk', root: File.exist?(path) ? File.realpath(path) : path }
               when 'ActiveStorage::Service::S3Service'
                 config = service.client.client.config
                 { adapter: 'S3', bucket: service.bucket.name, endpoint: config.endpoint.to_s, region: config.region }
               else
                 raise JrcMigrations::Error, 'MEDIA_STORAGE_UNSUPPORTED'
               end
    # Credentials, session tokens, retry policy and signing expiry are not
    # destination identity. Only this digest is persisted, never configuration.
    JrcMigrations::Catalog.digest(identity)
  end

  def self.verify!(media)
    service = ActiveStorage::Blob.services.fetch(media.service_name)
    raise JrcMigrations::Error, 'MEDIA_STORAGE_CHANGED' unless media.storage_identity.present? && fingerprint(service) == media.storage_identity

    service
  rescue KeyError
    raise JrcMigrations::Error, 'MEDIA_STORAGE_UNAVAILABLE'
  end
end
