class JrcMigrations::Execute
  def initialize(batch:, user:)
    @batch = batch
    @user = user
    @adapter = JrcMigrations::Catalog.adapter(batch.domain, account: batch.account, source: batch.source)
  end

  def call
    JrcMigrations::Access.authorize!(@batch.account, @user)
    # Serialize migration/NICO decisions while permitting native audit FKs to
    # take KEY SHARE on Account when their editor already holds the destination.
    @batch.account.with_lock('FOR NO KEY UPDATE') do
      @batch.with_lock do
        JrcMigrations::Access.authorize!(@batch.account, @user, lock: true)
        raise JrcMigrations::Error, 'PREVIEW_REQUIRED' unless @batch.status == 'previewed'

        @batch.items.order(:id).each { |item| execute!(item) }
        @batch.update!(status: 'executed', executed_at: Time.current, summary: @batch.items.group(:status).count,
                       accepted_at: nil, accepted_by_id: nil, acceptance_note: nil, reconciliation: {})
        JrcMigrations::Event.record!(batch: @batch, user: @user, action: 'EXECUTED', metadata: { summary: @batch.summary })
      end
    end
    @batch
  end

  private

  def execute!(item)
    unless %w[create update ignore].include?(item.decision)
      item.update!(status: 'blocked')
      return
    end
    @adapter.migration_item = item
    JrcMigrations::Item.transaction(requires_new: true) { apply!(item) }
  rescue JrcMigrations::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ActiveRecord::InvalidForeignKey => e
    code = e.is_a?(JrcMigrations::Error) ? e.message : 'DESTINATION_CONFLICT'
    item.reload
    before = item.before_data
    if e.is_a?(JrcMigrations::Error) && e.private_context.present?
      before = before.merge('storage_cleanup' => (Array(before['storage_cleanup']) + [e.private_context]).uniq)
    end
    item.update!(status: 'failed', error_code: code, before_data: before)
  ensure
    @adapter.migration_item = nil
  end

  def apply!(item)
    mapping = mapping_for(item)
    target = item.target_id && @adapter.scope.lock.find_by(id: item.target_id)
    verify_preview!(item, mapping, target)
    if item.decision == 'ignore'
      item.update!(status: 'ignored', migrated_at: Time.current)
    else
      write_target!(item, mapping, target)
    end
  end

  def verify_preview!(item, mapping, target)
    if item.decision == 'create'
      raise JrcMigrations::Error, 'PREVIEW_STALE' if mapping || @adapter.candidates(item.normalized_data).any?
    elsif !same_target?(item, mapping, target)
      raise JrcMigrations::Error, 'DESTINATION_CHANGED'
    end
  end

  def same_target?(item, mapping, target)
    target && mapping && mapping.target_id == target.id && @adapter.digest(target) == item.target_digest
  end

  def write_target!(item, mapping, target)
    before = previous_data(item, mapping, target)
    record = @adapter.write!(@adapter.build(item.normalized_data, target: target))
    mapping ||= JrcMigrations::Mapping.new(identity(item).merge(target_id: record.id))
    mapping.update!(batch: @batch, source_digest: item.source_digest, target_digest: @adapter.digest(record),
                    source_updated_at: @adapter.timestamp!(item.normalized_data['updated_at']), accepted_at: nil, accepted_by_id: nil)
    item.update!(status: 'applied', target_id: record.id, target_digest: mapping.target_digest, before_data: before, migrated_at: Time.current,
                 error_code: nil)
  rescue StandardError
    @adapter.rollback_write!(record) if record
    raise
  end

  def identity(item)
    { account_id: @batch.account_id, source: @batch.source, domain: @batch.domain, legacy_id: item.legacy_id }
  end

  def previous_data(item, mapping, target)
    before = target ? target.attributes.merge('migration_mapping' => mapping.attributes) : {}
    before['storage_cleanup'] = item.before_data['storage_cleanup'] if item.before_data['storage_cleanup'].present?
    before
  end

  def mapping_for(item)
    JrcMigrations::Mapping.lock.find_by(identity(item))
  end
end
