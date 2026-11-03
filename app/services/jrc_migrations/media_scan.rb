class JrcMigrations::MediaScan
  SCAN_FIELDS = %w[service_desk_scan_state service_desk_scan_adapter service_desk_scan_sha256 service_desk_scanned_at].freeze
  DOMAINS = %w[project_attachments project_task_attachments].freeze
  private_constant :SCAN_FIELDS, :DOMAINS

  def initialize(item:, user:)
    @item = item
    @batch = item.batch
    @user = user
  end

  def call
    snapshot = with_source_lock { start_scan! }
    verify_bytes!(snapshot)
    # The configured local daemon and storage readback run outside the native
    # Account/Batch/Item transaction. No request can supply a scanner endpoint.
    result = JrcServiceDesk::AttachmentScanner.new.scan(snapshot.fetch(:blob)).slice(*SCAN_FIELDS)
    verify_bytes!(snapshot)
    with_source_lock { persist_scan!(snapshot, result) }
    @batch
  end

  private

  def with_source_lock
    @batch.account.with_lock('FOR NO KEY UPDATE') do
      @batch.with_lock do
        @item.with_lock do
          JrcMigrations::Access.authorize!(@batch.account, @user, lock: true)
          yield
        end
      end
    end
  end

  def current_source!
    raise JrcMigrations::Error, 'UNSUPPORTED_MEDIA' unless DOMAINS.include?(@batch.domain)

    attachment = attached_source!
    authorize_parent!(attachment.record)
    media = attached_media!(attachment)
    mapping = source_mapping!(attachment)
    { blob: attachment.blob, media: media, sha256: media.source_sha256, identity: source_identity(attachment, media, mapping) }
  end

  def attached_source!
    adapter = JrcMigrations::Catalog.adapter(@batch.domain, account: @batch.account, source: @batch.source)
    attachment = adapter.scope.find_by(id: @item.target_id)
    raise JrcMigrations::Error, 'MEDIA_NOT_ATTACHED' unless attachment && @item.status.in?(%w[applied ignored])

    attachment
  end

  def attached_media!(attachment)
    media = JrcMigrations::MediaObject.where(account_id: @item.account_id, item_id: @item.id, status: 'attached').order(:generation).last
    raise JrcMigrations::Error, 'MEDIA_NOT_ATTACHED' unless media && media.blob_id == attachment.blob_id
    unless attachment.blob.key == media.storage_key && attachment.blob.service_name == media.service_name
      raise JrcMigrations::Error, 'MEDIA_SOURCE_CHANGED'
    end

    media
  end

  def source_identity(attachment, media, mapping)
    blob = attachment.blob
    [attachment.id, attachment.record_type, attachment.record_id, blob.id, blob.key, blob.service_name,
     mapping.id, mapping.source_digest, mapping.target_digest, media.id, @item.source_digest]
  end

  def source_mapping!(attachment)
    mapping = JrcMigrations::Mapping.find_by(account_id: @item.account_id, domain: @batch.domain, source: @batch.source,
                                             legacy_id: @item.legacy_id, target_id: attachment.id)
    raise JrcMigrations::Error, 'MEDIA_SOURCE_CHANGED' unless mapping && mapping.source_digest == @item.source_digest

    mapping
  end

  def authorize_parent!(record)
    project = record.is_a?(JrcProjects::Task) ? record.project : record
    capability = record.is_a?(JrcProjects::Task) ? 'projects.task.view' : 'projects.project.view'
    member = AccountUser.find_by(account_id: @batch.account_id, user_id: @user.id)
    allowed = JrcProjects::Authorization.allowed?(account_user: member, capability: capability, project: project, record: record)
    raise JrcMigrations::Error, 'MIGRATION_FORBIDDEN' unless allowed
  end

  def verify_bytes!(snapshot)
    actual = JrcMigrations::AttachmentStorage.sha256(snapshot.fetch(:blob))
    raise JrcMigrations::Error, 'ATTACHMENT_STORAGE_UNVERIFIED' unless actual == snapshot.fetch(:sha256)
  end

  def start_scan!
    snapshot = current_source!
    media = snapshot.fetch(:media)
    media.update!(scan_generation: media.scan_generation + 1, scan_token: SecureRandom.uuid, scan_started_at: Time.current)
    snapshot.merge(scan_generation: media.scan_generation, scan_token: media.scan_token)
  end

  def current_scan!(snapshot)
    current = current_source!
    raise JrcMigrations::Error, 'MEDIA_SOURCE_CHANGED' unless current.fetch(:identity) == snapshot.fetch(:identity)

    media = current.fetch(:media)
    unless media.scan_generation == snapshot.fetch(:scan_generation) && media.scan_token == snapshot.fetch(:scan_token)
      raise JrcMigrations::Error, 'MEDIA_SCAN_CHANGED'
    end

    current
  end

  def persist_scan!(snapshot, result)
    current = current_scan!(snapshot)
    media = current.fetch(:media)
    verdict = result['service_desk_scan_state']
    result = { 'service_desk_scan_state' => 'unavailable' } unless %w[clean infected unavailable].include?(verdict)
    if result['service_desk_scan_state'] == 'clean' && result['service_desk_scan_sha256'] != current.fetch(:sha256)
      raise JrcMigrations::Error, 'ATTACHMENT_STORAGE_UNVERIFIED'
    end

    blob = current.fetch(:blob)
    blob.update!(metadata: blob.metadata.merge(result))
    media.update!(scan_token: nil)
    JrcMigrations::Event.record!(batch: @batch, user: @user, action: 'MEDIA_SCANNED',
                                 metadata: { item_id: @item.id, media_id: current.fetch(:media).id, scan_state: result['service_desk_scan_state'] })
  end
end
