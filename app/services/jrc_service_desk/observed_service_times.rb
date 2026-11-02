# frozen_string_literal: true

# Wall time from native facts. Never substituted for calendar-based SLA elapsed time.
class JrcServiceDesk::ObservedServiceTimes
  def initialize(ticket, version, cycle)
    @ticket, @version, @cycle = ticket, version, cycle
  end

  def call
    start = @ticket.lifecycle_transitions.where(action: 'reopen').maximum(:occurred_at) || @ticket.opened_at
    first = @ticket.ticket_events.where(event_type: %w[first_response_observed first_response_recorded])
                   .where("(data->>'achieved_at')::timestamptz >= ?", start)
                   .order(Arel.sql("(data->>'achieved_at')::timestamptz"), :id).first
    mode = @version&.definition&.dig('sla', 'mode')
    { basis: 'elapsed_wall_time', started_at: start.iso8601(6),
      first_response: fact(first && Time.iso8601(first.data.fetch('achieved_at')), start),
      resolution: fact(@ticket.lifecycle_transitions.where(action: 'resolve').where('occurred_at >= ?', start).maximum(:occurred_at), start),
      closure: fact(@ticket.lifecycle_transitions.where(action: 'close').where('occurred_at >= ?', start).maximum(:occurred_at), start),
      result: @cycle ? 'available' : mode == 'not_applicable' ? 'not_applicable' : 'unavailable',
      pending_reason: mode == 'calendar_snapshot' && !@cycle ? JrcServiceDesk::SlaConfigurationState.reason(@ticket.latest_sla_snapshot, @version.rules.clock_kinds) || 'result_unavailable' : nil }
  end

  private

  def fact(time, start)
    time && { occurred_at: time.iso8601(6), elapsed_seconds: (time - start).to_f }
  end
end
