class JrcMigrations::Preview
  def initialize(batch:, user:)
    @batch = batch
    @user = user
    @adapter = JrcMigrations::Catalog.adapter(batch.domain, account: batch.account, source: batch.source)
  end

  def call
    JrcMigrations::Access.authorize!(@batch.account, @user)
    @batch.account.with_lock('FOR NO KEY UPDATE') do
      @batch.with_lock do
        JrcMigrations::Access.authorize!(@batch.account, @user, lock: true)
        @batch.items.order(:id).each { |item| preview!(item) }
        @batch.update!(status: 'previewed', summary: @batch.items.group(:decision).count)
        JrcMigrations::Event.record!(batch: @batch, user: @user, action: 'PREVIEWED', metadata: { summary: @batch.summary })
      end
    end
    verify_reserved_media!
    @batch
  end

  private

  def verify_reserved_media!
    return unless @adapter.is_a?(JrcMigrations::Adapters::ProjectAttachment)

    @batch.items.where(decision: %w[create update], status: 'previewed').order(:id).each do |item|
      media = JrcMigrations::MediaObject.where(account_id: @batch.account_id, item_id: item.id).order(:generation).last
      next unless media&.status.in?(%w[reserved verifying verification_required])

      JrcMigrations::MediaVerification.new(media: media, user: @user).call
    end
  end

  def preview!(item)
    mapping = JrcMigrations::Mapping.find_by(account_id: @batch.account_id, source: @batch.source,
                                             domain: @batch.domain, legacy_id: item.legacy_id)
    target = mapping && @adapter.scope.find_by(id: mapping.target_id)
    decision, code = decision_for(item, mapping, target)
    if %w[create update].include?(decision)
      prepared = @adapter.build(item.normalized_data, target: target)
      @adapter.reserve_media!(item, prepared)
    end
    item.update!(decision: decision, status: 'previewed', error_code: code, validation_errors: [],
                 target_id: target&.id, target_digest: target && @adapter.digest(@adapter.scope.find(target.id)))
  rescue JrcMigrations::Error => e
    item.update!(decision: 'reject', status: 'previewed', error_code: e.message)
  end

  def decision_for(item, mapping, target)
    return fresh_decision(item) unless mapping
    return %w[review DESTINATION_MISSING] unless target
    return %w[review DESTINATION_CHANGED] unless @adapter.digest(target) == mapping.target_digest
    return ['ignore', nil] if mapping.source_digest == item.source_digest
    return %w[reject APPEND_ONLY_DESTINATION] unless @adapter.update_allowed?

    incoming = @adapter.timestamp!(item.normalized_data['updated_at'])
    return %w[review SOURCE_VERSION_CONFLICT] if incoming <= mapping.source_updated_at

    ['update', nil]
  end

  def fresh_decision(item)
    @adapter.candidates(item.normalized_data).empty? ? ['create', nil] : %w[review MATCH_REQUIRES_REVIEW]
  end
end
