class JrcNico::ReservationReconciler
  def initialize(account:)
    @account = account
  end

  # Default is read-only. Applying rechecks every candidate under both locks.
  def call(dry_run: true)
    records(dry_run: dry_run).map do |record|
      if dry_run
        classification(record)
      else
        @account.with_lock do
          record.with_lock do
            row = classification(record)
            apply!(record, row) unless %w[active uncertain_manual_review settled].include?(row[:classification])
            row
          end
        end
      end
    end
  end

  private

  def records(dry_run:)
    [JrcNico::Inference, JrcNico::Run].flat_map do |model|
      scope = model.where(account: @account)
      scope = if dry_run
                scope.where('reserved_tokens > 0').or(scope.where(status: %w[running queued]))
              else
                scope.where(status: %w[running queued]).or(scope.where(JrcNico::ReservationLedger.receipt_condition(model)).where('reserved_tokens > 0'))
              end
      scope.order(:id).to_a
    end
  end

  def classification(record)
    type = record.is_a?(JrcNico::Run) ? 'run' : 'inference'
    events = JrcNico::ReservationLedger.new(record).events
    fallback = type == 'run' ? record.started_at || record.created_at : record.created_at
    lease = record.lease_expires_at || (fallback + JrcNico::ReservationLedger::LEASE)
    value = if record.status == 'queued' && record.created_at < JrcNico::ReservationLedger::QUEUE_TTL.ago
              'queued_not_executed'
            elsif record.status == 'queued' || (record.status == 'running' && lease.future?)
              'active'
            elsif events.exists?
              'usage_already_recorded'
            elsif record.accounting['version'] == 1 && record.accounting['dispatch_started_at'].nil? && !lease.future?
              'expired_not_dispatched'
            elsif record.status == 'running' && !lease.future?
              'abandoned_unknown'
            elsif record.reserved_tokens.positive?
              'uncertain_manual_review'
            else
              'settled'
            end
    { account_id: @account.id, type: type, id: record.id, status: record.status, reserved_tokens: record.reserved_tokens,
      created_at: record.created_at, classification: value, release_tokens: %w[queued_not_executed expired_not_dispatched usage_already_recorded].include?(value) }
  end

  def apply!(record, row)
    audit = { 'policy' => 'nico-reservation-v1', 'actor' => 'system', 'classification' => row[:classification],
              'at' => Time.current.iso8601(6), 'previous_status' => record.status, 'previous_reserved_tokens' => record.reserved_tokens,
              'released' => row[:release_tokens] }
    return if record.accounting.dig('reconciliation', 'classification') == row[:classification]

    basis = if row[:classification] == 'usage_already_recorded'
              JrcNico::ReservationLedger.new(record).events.first.metadata['usage_estimated'] == true ? 'estimated' : 'confirmed'
            else
              row[:release_tokens] ? 'not_executed' : 'unknown'
            end
    history = Array(record.accounting['reconciliation_history']) + [audit]
    record.accounting = record.accounting.merge('basis' => basis, 'reconciliation' => audit, 'reconciliation_history' => history)
    record.reserved_tokens = 0 if row[:release_tokens]
    if record.is_a?(JrcNico::Run)
      if record.status == 'queued'
        record.assign_attributes(status: 'cancelled', error_code: 'queue_expired_not_executed', finished_at: Time.current)
      elsif record.status == 'running'
        code = row[:release_tokens] ? 'interrupted_reconciled' : 'interrupted_unknown_outcome'
        record.assign_attributes(status: 'failed', error_code: code, finished_at: Time.current)
      end
    elsif record.status != 'completed'
      record.status = row[:release_tokens] ? 'failed' : 'unknown'
    end
    record.save!
  end
end
