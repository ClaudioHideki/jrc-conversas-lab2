# frozen_string_literal: true

# Retries only explicit, confirmed provider failures. Unknown effects are never
# repeated and policy/authorization/recipient changes fail closed on every try.
class JrcServiceDesk::NotificationRetryJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(delivery_id)
    original = JrcServiceDesk::NotificationDelivery.find(delivery_id)
    original.unit.with_lock do
      original.reload
      next unless original.state == 'failed'

      policy = original.notification_policy_version
      settings = policy&.settings || {}
      next unless original.attempt_number < settings.fetch('max_attempts', 1)
      next unless JrcServiceDesk::NotificationEngine.blocker(original).nil?

      origin = original.ticket_note_id ? { ticket_note_id: original.ticket_note_id } : { ticket_event_id: original.ticket_event_id }
      fields = origin.merge(channel: original.channel, recipient_contact_id: original.recipient_contact_id,
                            attempt_number: original.attempt_number + 1)
      next if JrcServiceDesk::NotificationDelivery.exists?(fields)

      row = original.dup
      row.assign_attributes(fields.merge(original_delivery: original.original_delivery || original, message: nil, payload_digest: nil,
                                         provider_id: nil, request_key: nil, request_fingerprint: nil, state: 'queued', reason: nil,
                                         sent_at: nil, dispatch_started_at: nil, delivered_at: nil, read_at: nil, reconciled_at: nil,
                                         not_before: JrcServiceDesk::NotificationControls.new(settings).next_time(Time.current + settings.fetch('backoff_minutes').minutes)))
      row.save!
    end
  end
end
