# Timer intent is stored on the native run; publish its job only after the outer transaction commits.
module JrcRelationship::PlaybookFlowScheduling
  extend ActiveSupport::Concern

  included do
    after_save :remember_relationship_continuation
    after_save :remember_relationship_webhook
    after_commit :schedule_relationship_continuation, on: %i[create update]
    after_commit :schedule_relationship_webhook, on: %i[create update]
    after_rollback :clear_relationship_scheduling_intents
  end

  private

  def schedule_relationship_continuation
    return unless @relationship_continuation_intent
    return unless JrcRelationship::PlaybookFlowContinuation.managed?(self)
    return unless %w[waiting delayed].include?(status) && wake_at
    return unless @relationship_continuation_intent == [id, wake_version, wake_at.utc.iso8601(6)]

    JrcRelationship::PlaybookFlowResumeJob.set(wait_until: wake_at).perform_later(id, wake_version)
  ensure
    @relationship_continuation_intent = nil
  end

  def remember_relationship_continuation
    return unless JrcRelationship::PlaybookFlowContinuation.managed?(self)
    return unless saved_change_to_wake_at? || saved_change_to_wake_version? || saved_change_to_status?

    @relationship_continuation_intent = if %w[waiting delayed].include?(status) && wake_at
                                         [id, wake_version, wake_at.utc.iso8601(6)]
                                       end
  end

  def schedule_relationship_webhook
    return unless @relationship_webhook_intent
    return unless JrcRelationship::PlaybookFlowContinuation.managed?(self) && status == 'waiting'

    records = JrcRelationship::PlaybookFlowWebhookJournal.new(self).verify_integrity!
    record = records[node_id]
    if @relationship_webhook_intent == [id, node_id] && record && record['state'] == 'queued'
      JrcRelationship::PlaybookFlowWebhookJob.perform_later(id, node_id)
    end
  rescue ArgumentError, KeyError
    # Do not propagate a forged intent from a callback after its row committed.
    # Block the native Run and publish no transport job or payload diagnostics.
    self.class.where(id: id).update_all(status: 'paused', wake_at: nil, error: 'playbook_flow_webhook_authorization_blocked')
  ensure
    @relationship_webhook_intent = nil
  end

  def remember_relationship_webhook
    return unless JrcRelationship::PlaybookFlowContinuation.managed?(self)
    return unless saved_change_to_settings? || saved_change_to_status?

    record = settings.dig(JrcRelationship::PlaybookFlowWebhookJournal::KEY, 'records', node_id)
    @relationship_webhook_intent = status == 'waiting' && record.is_a?(Hash) && record['state'] == 'queued' ? [id, node_id] : nil
  end

  def clear_relationship_scheduling_intents
    @relationship_continuation_intent = nil
    @relationship_webhook_intent = nil
  end
end
