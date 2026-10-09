# frozen_string_literal: true

class JrcServiceDesk::ResendNotificationService < JrcServiceDesk::BaseService
  def call(delivery:, receipt:, reason:, idempotency_key:)
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    with_ticket(delivery.ticket_id, :add_note?) do |ticket|
      ticket.unit.lock!
      preview = JrcServiceDesk::NotificationResendPreview.new(row: delivery.reload, context: context)
      plan = preview.verify!(receipt, reason: reason)
      raise ArgumentError, 'Current notification dependencies are unavailable' unless plan[:available]

      existing = JrcServiceDesk::NotificationDelivery.find_by(account: context.account, execution_membership: actor_membership, request_key: key)
      fingerprint = fingerprint(delivery, plan)
      next verify_replay(existing, fingerprint) if existing

      create_attempt(preview.candidate, delivery, key: key, reason: reason, fingerprint: fingerprint)
    end
  end

  private

  def verify_replay(row, fingerprint)
    raise JrcServiceDesk::IdempotencyConflict unless row.request_fingerprint == fingerprint

    row
  end

  def fingerprint(original, plan)
    fields = plan.slice(:reason, :recipient, :policy_digest, :source_digest, :content)
    JrcServiceDesk::CanonicalJson.digest(fields.merge(original_delivery_id: original.id))
  end

  def next_attempt(origin, channel)
    JrcServiceDesk::NotificationDelivery.where(origin.merge(channel: channel)).maximum(:attempt_number).to_i + 1
  end

  def create_attempt(row, original, key:, reason:, fingerprint:)
    origin = row.ticket_note_id ? { ticket_note_id: row.ticket_note_id } : { ticket_event_id: row.ticket_event_id }
    row.assign_attributes(original_delivery: original, request_key: key, request_fingerprint: fingerprint,
                          attempt_number: next_attempt(origin, row.channel),
                          dispatch_started_at: nil, sent_at: nil, delivered_at: nil, read_at: nil, reconciled_at: nil)
    row.save!
    JrcServiceDesk::TicketEvent.create!(account: row.account, unit: row.unit, ticket: row.ticket, actor_membership: actor_membership,
                                        event_type: 'notification_resend_requested', visibility: 'internal',
                                        data: { 'original_delivery_id' => original.id, 'delivery_id' => row.id, 'reason' => reason })
    row
  end
end
