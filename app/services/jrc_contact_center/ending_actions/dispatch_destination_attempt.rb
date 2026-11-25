# frozen_string_literal: true

require 'redis'
require 'redis-client'

# A new typed attempt is already durable work. Delivery never creates another
# intent or changes an outcome. A broker outage cannot undo an ACW/native commit.
class JrcContactCenter::EndingActions::DispatchDestinationAttempt
  def self.call(attempt)
    # An early callback inside a nonjoinable transaction must not leak work.
    # The bounded reconciler can recover it after the actual outer commit.
    return false if attempt.class.connection.transaction_open?
    return false if JrcContactCenter::EndingDestinationOutcome.exists?(account_id: attempt.account_id, attempt_id: attempt.id)

    job = JrcContactCenter::EndingDestinationJob.perform_later(attempt.account_id, attempt.id)
    warn_pending(attempt, 'not_enqueued') unless job
    job || false
  rescue ActiveJob::EnqueueError, Redis::BaseError, RedisClient::Error => e
    warn_pending(attempt, e.class.name)
    false
  end

  def self.warn_pending(attempt, code)
    Rails.logger.warn({ event: 'ending_destination_delivery_pending', account_id: attempt.account_id,
                        attempt_id: attempt.id, error_class: code }.to_json)
  end
  private_class_method :warn_pending
end
