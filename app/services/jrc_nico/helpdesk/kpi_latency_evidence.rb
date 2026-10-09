# frozen_string_literal: true

class JrcNico::Helpdesk::KpiLatencyEvidence
  def initialize(context)
    @context = context
  end

  def call(role, events, durations, ids)
    { 'recipient_role' => role, 'missing_delivery' => events.size - durations.size,
      'event_ids' => events.map(&:id), 'anchor' => 'source_occurrence', 'queue_lag_included' => true,
      'elapsed_seconds' => durations, 'elapsed_minutes' => durations.map { |seconds| seconds / 60.0 },
      'samples' => events.filter_map { |event| sample(event, ids) }, 'coverage' => receipt_states(events, ids) }
      .merge(duration_summary(durations))
  end

  def sample(event, ids)
    receipt = JrcNico::Helpdesk::DeliveryReceipt.where(account: @context.account, source_type: 'event', source_id: event.id,
                                                       recipient_id: ids, state: 'delivered').order(:delivered_at).first
    anchor = event.evidence['source_occurred_at'] ? Time.iso8601(event.evidence['source_occurred_at']) : event.detected_at
    receipt && { 'event_id' => event.id, 'receipt_id' => receipt.id, 'elapsed_seconds' => receipt.delivered_at - anchor }
  end

  private

  def receipt_states(events, ids)
    JrcNico::Helpdesk::DeliveryReceipt.where(account: @context.account, source_type: 'event', source_id: events.map(&:id), recipient_id: ids)
                                      .group(:state).count
  end

  def duration_summary(durations)
    sorted = durations.sort
    { 'maximum_seconds' => durations.max, 'median_seconds' => median_seconds(sorted),
      'p95_seconds' => sorted.empty? ? nil : sorted[(sorted.size * 0.95).ceil - 1] }
  end

  def median_seconds(sorted)
    return if sorted.empty?

    middle = sorted.size / 2
    sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
  end
end
