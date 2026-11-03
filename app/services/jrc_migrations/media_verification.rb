# Commit the reservation before checking physical storage; never infer ownership
# from an existing object or from the current storage name alone.
class JrcMigrations::MediaVerification
  def initialize(media:, user:)
    @media = media
    @user = user
  end

  def call
    3.times do
      @token = with_source_lock { claim! }
      return @media unless @token

      service = JrcMigrations::StorageIdentity.verify!(@media)
      occupied = service.exist?(@media.storage_key)
      with_source_lock { finish!(occupied) }
      return @media if @media.status == 'planned'
    end
    raise JrcMigrations::Error, 'MEDIA_KEY_ALLOCATION_FAILED'
  rescue StandardError
    release_claim!
    raise
  end

  private

  def with_source_lock
    @media.account.with_lock('FOR NO KEY UPDATE') do
      @media.batch.with_lock do
        @media.item.with_lock do
          @media.with_lock do
            JrcMigrations::Access.authorize!(@media.account, @user, lock: true)
            yield
          end
        end
      end
    end
  end

  def claim!
    JrcMigrations::StorageIdentity.verify!(@media)
    return if @media.status == 'planned'

    if @media.status == 'verifying' && @media.claimed_at && @media.claimed_at > 5.minutes.ago
      raise JrcMigrations::Error, 'MEDIA_VERIFICATION_IN_PROGRESS'
    end
    raise JrcMigrations::Error, 'MEDIA_SOURCE_CHANGED' unless @media.status.in?(%w[reserved verifying verification_required])

    token = SecureRandom.uuid
    @media.update!(status: 'verifying', claim_token: token, claimed_at: Time.current, error_code: nil)
    token
  end

  def finish!(occupied)
    raise JrcMigrations::Error, 'MEDIA_SOURCE_CHANGED' unless @media.status == 'verifying' && @media.claim_token == @token

    JrcMigrations::StorageIdentity.verify!(@media)
    if occupied
      @media.update!(status: 'kept', checked_at: Time.current, error_code: 'MEDIA_KEY_OCCUPIED', claim_token: nil, claimed_at: nil)
      rotate!
    else
      @media.update!(status: 'planned', absence_verified_at: Time.current, checked_at: Time.current,
                     error_code: nil, claim_token: nil, claimed_at: nil)
    end
  end

  def rotate!
    @media = JrcMigrations::MediaObject.create!(account: @media.account, batch: @media.batch, item: @media.item,
                                                generation: @media.generation + 1, service_name: @media.service_name,
                                                storage_key: SecureRandom.base36(28),
                                                source_sha256: @media.source_sha256, byte_size: @media.byte_size,
                                                storage_identity: @media.storage_identity)
  end

  def release_claim!
    return unless @token

    with_source_lock do
      if @media.status == 'verifying' && @media.claim_token == @token
        @media.update!(status: 'verification_required', claim_token: nil, claimed_at: nil,
                       checked_at: Time.current, error_code: 'MEDIA_VERIFICATION_REQUIRED')
      end
    end
  rescue StandardError
    # A revoked caller or lost database leaves the durable lease for a later
    # authorized retry. No byte deletion is permitted by this verification path.
    nil
  end
end
