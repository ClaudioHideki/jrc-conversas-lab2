# frozen_string_literal: true

class JrcContactCenter::CallFactContribution
  def initialize(session:)
    @session = session
  end

  def call
    queue_id = @session.f1_data['entry_queue_id'] || @session.current_queue_id
    queue = JrcContactCenter::Queue.where(account_id: @session.account_id).find(queue_id) if queue_id
    zone = Time.find_zone!(@session.account.reporting_timezone.presence || 'UTC')
    { dimensions: { fact_date: @session.started_at.in_time_zone(zone).to_date.iso8601, unit_id: queue&.unit_id,
                    queue_id: queue&.id, account_user_id: nil, direction: @session.direction },
      values: counters.merge(durations), measurements: measurements }.deep_stringify_keys
  end

  private

  def counters
    {
      offered_count: @session.f1_data['offered_at'] ? 1 : 0, answered_count: @session.answered_at ? 1 : 0,
      abandoned_count: !@session.answered_at && @session.f1_data['outcome'] == 'abandoned' ? 1 : 0,
      transferred_count: @session.f1_data['transferred'] ? 1 : 0, fallback_count: @session.fallback_events.exists? ? 1 : 0
    }
  end

  def durations
    held = @session.f1_data.fetch('hold_seconds', 0)
    {
      wait_seconds: measured_wait, talk_seconds: [talk_span - held, 0].max, hold_seconds: held,
      acw_seconds: acw_events.sum { |event| [(event.ended_at - event.started_at).to_i, 0].max }
    }
  end

  def measured_wait
    queued = @session.f1_data['entry_queued_at']
    return 0 unless queued && @session.answered_at

    [(@session.answered_at - Time.iso8601(queued)).to_i, 0].max
  end

  def talk_span
    intervals = @session.legs.where.not(answered_at: nil).where.not(ended_at: nil).order(:answered_at).pluck(:answered_at, :ended_at)
    intervals = [[@session.answered_at, @session.ended_at]] if intervals.empty? && @session.answered_at
    total, = intervals.reduce([0, nil]) do |(seconds, last_end), (started, ended)|
      lower_bound = last_end ? [started, last_end].max : started
      [seconds + [(ended - lower_bound).to_i, 0].max, last_end ? [ended, last_end].max : ended]
    end
    total
  end

  def acw_events
    @acw_events ||= JrcContactCenter::AgentStateEvent.where(account_id: @session.account_id, state: 'acw')
                                                     .where("metadata ->> 'jrc_call_session_id' = ?", @session.id.to_s)
                                                     .where.not(ended_at: nil).to_a
  end

  def measurements
    {
      wait_measured_count: @session.answered_at && @session.f1_data['entry_queued_at'] ? 1 : 0,
      talk_measured_count: @session.answered_at ? 1 : 0, acw_completed_count: acw_events.size,
      wait_measured_seconds: measured_wait,
      talk_measured_seconds: durations[:talk_seconds], acw_measured_seconds: durations[:acw_seconds]
    }
  end
end
