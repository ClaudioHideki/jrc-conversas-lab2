class JrcMigrations::MediaRecovery
  CLAIM_TTL = 5.minutes
  private_constant :CLAIM_TTL

  def initialize(media:, user:)
    @media = media
    @user = user
  end

  def call
    JrcMigrations::Access.authorize!(@media.account, @user)
    recover!
  end

  # The scheduled sweeper can compensate only a ledger-owned key; it cannot
  # import, attach, scan, accept evidence or delete a registered Blob.
  def self.sweep(media)
    new(media: media, user: nil).send(:sweep!)
  end

  # Transaction callbacks have observed an actual rollback. Unlike a scheduled
  # absence check, they must fence retries before compensating the old upload.
  def self.compensate(media)
    new(media: media, user: nil).send(:recover!)
  end

  private

  def sweep!
    service = JrcMigrations::StorageIdentity.verify!(@media)
    if @media.status.in?(%w[planned cleaned]) && !service.exist?(@media.storage_key)
      with_source_lock { @media.update!(checked_at: Time.current) unless @media.status.in?(%w[attached kept]) }
      return @media
    end

    recover!
  end

  def recover!
    @token = with_source_lock { claim! }
    return @media unless @token

    status, code = remove_owned_object
    with_source_lock { finish!(status, code) }
    @media
  end

  def with_source_lock(&)
    @media.account.with_lock('FOR NO KEY UPDATE') do
      @media.batch.with_lock do
        @media.item.with_lock do
          @media.with_lock(&)
        end
      end
    end
  end

  def claim!
    JrcMigrations::Access.authorize!(@media.account, @user, lock: true) if @user
    return if @media.status.in?(%w[attached kept])

    JrcMigrations::StorageIdentity.verify!(@media)

    if registered_blob?
      @media.update!(status: 'kept', checked_at: Time.current, claim_token: nil, claimed_at: nil, error_code: nil)
      audit!
      return
    end
    ensure_recoverable!

    token = SecureRandom.uuid
    @media.update!(status: 'recovering', claim_token: token, claimed_at: Time.current, error_code: nil)
    token
  end

  def ensure_recoverable!
    raise JrcMigrations::Error, 'MEDIA_PREVIEW_REQUIRED' unless @media.absence_verified_at

    return unless @media.status == 'recovering' && @media.claimed_at && @media.claimed_at > CLAIM_TTL.ago

    raise JrcMigrations::Error, 'MEDIA_RECOVERY_IN_PROGRESS'
  end

  def registered_blob?
    ActiveStorage::Blob.exists?(service_name: @media.service_name, key: @media.storage_key)
  end

  def remove_owned_object
    return ['kept', nil] if registered_blob?

    service = JrcMigrations::StorageIdentity.verify!(@media)
    service.delete(@media.storage_key)
    raise IOError if service.exist?(@media.storage_key)

    ['cleaned', nil]
  rescue StandardError
    %w[cleanup_required ATTACHMENT_CLEANUP_REQUIRED]
  end

  def finish!(status, code)
    return unless @media.status == 'recovering' && @media.claim_token == @token

    @media.update!(status: status, error_code: code, checked_at: Time.current, claim_token: nil, claimed_at: nil)
    audit!
  end

  def audit!
    JrcMigrations::Event.record!(batch: @media.batch, user: @user, action: 'MEDIA_RECOVERED',
                                 metadata: { item_id: @media.item_id, media_id: @media.id, status: @media.status })
  end
end
