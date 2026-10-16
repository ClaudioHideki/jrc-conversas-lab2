# The signed Playbook journal is an independent outbox. Queue scans alone
# cannot prove that a dispatched or unknown HTTP effect was drained.
class JrcFlows::OwnershipPlaybook
  def self.runs(scope)
    JrcFlowRun.joins(:conversation).where(account_id: scope.account_id, conversations: { inbox_id: scope.inbox_id })
              .where('settings ? :key', key: JrcRelationship::PlaybookFlowWebhookJournal::KEY)
  end

  def self.cancel_queued!(scope)
    runs(scope).find_each do |run|
      run.with_lock do
        journal = JrcRelationship::PlaybookFlowWebhookJournal.new(run)
        journal.verify_integrity!.each do |node_id, record|
          next unless record['state'] == 'queued'

          journal.update!(node_id, state: 'cancelled', completed_at: Time.current.iso8601(6))
          run.update!(status: 'paused', wake_at: nil, error: 'Executor legacy fechado antes do webhook.')
        end
      end
    end
  end

  def self.counts(scope)
    result = { jobs: 0, effects: 0 }
    runs(scope).find_each do |run|
      JrcRelationship::PlaybookFlowWebhookJournal.new(run).verify_integrity!.each_value do |record|
        result[:jobs] += 1 if record['state'] == 'queued'
        result[:effects] += 1 if %w[dispatching unknown].include?(record['state'])
      end
    rescue ArgumentError, KeyError
      result[:effects] += 1
    end
    result
  end
end
