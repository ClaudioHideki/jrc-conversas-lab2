class JrcMigrations::Reconciliation
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
        calculate_report!
      end
    end
  end

  def calculate_report!
    report = { 'total' => @batch.items.count, 'matched' => 0, 'divergent' => 0, 'blocked' => 0,
               'checked_at' => Time.current.iso8601, 'source_evidence' => 'staged_rows', 'official_source_verified' => false }
    @batch.items.each do |item|
      result = result_for(item)
      report[result] += 1
    end
    @batch.update!(reconciliation: report)
    JrcMigrations::Event.record!(batch: @batch, user: @user, action: 'RECONCILED', metadata: { report: report })
    report
  end
  private :calculate_report!

  def accept!(note:)
    raise JrcMigrations::Error, 'ACCEPTANCE_NOTE_REQUIRED' unless note.is_a?(String) && note.strip.length.between?(3, 2000)

    @batch.account.with_lock('FOR NO KEY UPDATE') do
      @batch.with_lock do
        JrcMigrations::Access.authorize!(@batch.account, @user, lock: true)
        verify_report!
        accept_items!
        @batch.update!(status: 'accepted', accepted_at: Time.current, accepted_by: @user, acceptance_note: note.strip)
        JrcMigrations::Event.record!(batch: @batch, user: @user, action: 'ACCEPTED', metadata: { note: note.strip })
      end
    end
    @batch
  end

  private

  def result_for(item)
    return 'matched' if matches?(item)

    %w[applied ignored].include?(item.status) ? 'divergent' : 'blocked'
  end

  def verify_report!
    report = call
    return if @batch.status.in?(%w[executed accepted]) && report['total'].positive? && report['matched'] == report['total']

    raise JrcMigrations::Error, 'RECONCILIATION_REQUIRED'
  end

  def accept_items!
    @batch.items.each do |item|
      @adapter.scope.lock.find(item.target_id)
      raise JrcMigrations::Error, 'RECONCILIATION_REQUIRED' unless matches?(item)

      mapping_for(item).update!(accepted_at: Time.current, accepted_by: @user)
    end
  end

  def mapping_for(item)
    JrcMigrations::Mapping.find_by(account_id: @batch.account_id, source: @batch.source, domain: @batch.domain, legacy_id: item.legacy_id)
  end

  def matches?(item)
    return false unless %w[applied ignored].include?(item.status)

    mapping = mapping_for(item)
    target = @adapter.scope.find_by(id: item.target_id)
    return false unless same_source?(mapping, target, item)
    return false unless @adapter.digest(target) == mapping.target_digest && mapping.target_digest == item.target_digest

    @adapter.build(item.normalized_data, target: target)
    true
  rescue JrcMigrations::Error
    false
  end

  def same_source?(mapping, target, item)
    mapping && target && mapping.target_id == target.id && mapping.source_digest == item.source_digest
  end
end
