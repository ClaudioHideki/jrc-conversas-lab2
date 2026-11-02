class JrcBroker::WebhookObligationJob < ApplicationJob
  queue_as :medium
  self.log_arguments = false

  def perform(id)
    row = JrcBrokerWebhookObligation.find_by(id: id)
    return unless row

    token = SecureRandom.uuid
    claimed = claim(row, token)
    return unless claimed

    dispatch(row, token)
  rescue StandardError => e
    raise unless claimed

    record_failure(row, token, e)
  end

  private

  def claim(row, token)
    row.with_lock do
      next false unless due?(row)

      if row.attempts >= 8
        row.update!(state: 'failed', lease_token: nil, lease_until: nil, last_error_code: 'JRC_BROKER_DELIVERY_OUTCOME_UNCERTAIN')
        fail_message(row, JrcBroker::WebhookDelivery::Unavailable.new)
        next false
      end
      row.update!(state: 'running', lease_token: token, lease_until: 5.minutes.from_now, attempts: row.attempts + 1)
      true
    end
  end

  def due?(row)
    (row.state == 'pending' && row.available_at <= Time.current) ||
      (row.state == 'running' && row.lease_until && row.lease_until <= Time.current)
  end

  def dispatch(row, token)
    unless row.current_binding?
      settle(row, token, state: 'rejected', last_error_code: 'JRC_BROKER_DELIVERY_CONTEXT_CHANGED',
                         failure: JrcBroker::WebhookDelivery::ContextChanged.new)
      return
    end

    Webhooks::Trigger.execute(row.url, row.payload.deep_symbolize_keys, :api_inbox_webhook,
                              secret: row.message.inbox.channel.secret, delivery_id: row.delivery_id, strict: true)
    settle(row, token, state: 'delivered', last_error_code: nil)
  end

  def record_failure(row, token, error)
    retryable = JrcBroker::WebhookDelivery.new(row.message).retryable?(error)
    state = retryable && row.attempts < 8 ? 'pending' : 'failed'
    settle(row, token, failure: state == 'failed' ? error : nil,
                       state: state, available_at: [2**row.attempts, 900].min.seconds.from_now,
                       last_error_code: retryable ? 'JRC_BROKER_DELIVERY_UNAVAILABLE' : 'JRC_BROKER_DELIVERY_REJECTED')
  end

  def settle(row, token, failure: nil, **attributes)
    JrcBrokerWebhookObligation.transaction do
      owned = JrcBrokerWebhookObligation.where(id: row.id, state: 'running', lease_token: token)
      # Atomic compare-and-set must include the lease in the UPDATE predicate.
      changed = owned.update_all(attributes.merge(lease_token: nil, lease_until: nil, updated_at: Time.current)) # rubocop:disable Rails/SkipsModelValidations
      fail_message(row, failure) if changed == 1 && failure
      changed
    end
  end

  def fail_message(row, error)
    row.message.with_lock { JrcBroker::WebhookDelivery.new(row.message).handle_failure(error) }
  end
end
