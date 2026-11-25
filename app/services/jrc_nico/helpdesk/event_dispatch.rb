# frozen_string_literal: true

require 'redis'
require 'redis-client'

# Delivery only: no grant, state/provenance mutation, tool call or provider API.
# A transport failure leaves the native detected Event visible and recoverable
# by MonitorJob. Never turn a committed destination into a false rollback.
class JrcNico::Helpdesk::EventDispatch
  def self.call(event)
    # A nonjoinable surrounding transaction can run an early callback. Keep
    # its durable intent pending; the independent monitor will deliver it.
    return false if event.class.connection.transaction_open?

    return false unless event.state == 'detected'

    result = JrcNico::Helpdesk::EventJob.perform_later(event.id)
    warn_pending(event, 'not_enqueued') unless result
    result
  rescue ActiveJob::EnqueueError, Redis::BaseError, RedisClient::Error => e
    warn_pending(event, e.class.name)
    false
  end

  def self.warn_pending(event, code)
    Rails.logger.warn({ event: 'nico_helpdesk_delivery_pending', account_id: event.account_id,
                        event_id: event.id, error_class: code }.to_json)
  end
  private_class_method :warn_pending
end
