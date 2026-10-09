# frozen_string_literal: true

# Reconciles evidence already recorded by the native provider. It never sends.
class JrcServiceDesk::NotificationReceipt
  ACCEPTED = %w[sent delivered read].freeze
  RANK = { 'sent' => 1, 'delivered' => 2, 'read' => 3 }.freeze

  def initialize(row)
    @row = row
  end

  def call
    @row.with_lock do
      message = @row.message&.reload
      next @row unless trustworthy?(message)

      state = evidence_state(message)
      next @row unless advances?(state)

      persist(message, state)
      audit(state)
      @row
    end
  end

  private

  def trustworthy?(message)
    return false unless message && @row.state != 'blocked'
    return false unless message.account_id == @row.account_id && message.conversation_id == @row.conversation_id
    return false unless message.content_attributes['service_desk_delivery_id'].to_s == @row.id.to_s

    @row.payload_digest.present? && @row.payload_digest == JrcServiceDesk::NotificationExecution.payload_digest(message, @row)
  end

  def evidence_state(message)
    return message.status if %w[delivered read failed].include?(message.status)

    'sent' if message.source_id.present?
  end

  def advances?(state)
    return false unless state && state != @row.state
    return false if ACCEPTED.include?(@row.state) && (ACCEPTED.exclude?(state) || RANK.fetch(state) <= RANK.fetch(@row.state))

    true
  end

  def persist(message, state)
    now = Time.current
    @row.update!(timestamps(state, now).merge(state: state, provider_id: message.source_id, reconciled_at: now,
                                              reason: state == 'failed' ? 'provider_failure' : nil))
  end

  def timestamps(state, now)
    { sent_at: @row.sent_at || (ACCEPTED.include?(state) ? now : nil),
      delivered_at: @row.delivered_at || (%w[delivered read].include?(state) ? now : nil),
      read_at: @row.read_at || (state == 'read' ? now : nil) }
  end

  def audit(state)
    return unless @row.execution_membership.reload.active?

    JrcServiceDesk::TicketEvent.create!(account: @row.account, unit: @row.unit, ticket: @row.ticket,
                                        actor_membership: @row.execution_membership, event_type: 'notification_delivery_updated',
                                        visibility: 'internal',
                                        data: { 'delivery_id' => @row.id, 'channel' => @row.channel, 'state' => state })
  end
end
