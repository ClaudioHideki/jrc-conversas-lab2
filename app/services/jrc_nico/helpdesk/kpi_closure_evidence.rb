# frozen_string_literal: true

# Both named observations retain their own real temporal basis; C10 remains a business decision.
class JrcNico::Helpdesk::KpiClosureEvidence
  def initialize(context)
    @context = context
  end

  def overdue(close, config)
    clock = completion_clock(close)
    return unless clock

    seconds = config['basis'] == 'business' ? clock.elapsed_seconds.to_f - clock.budget_seconds : clock.achieved_at - clock.due_at
    [seconds, 0].max
  end

  def observations(cohort, overdue, config)
    age = cohort.map { |close| close.occurred_at - close.ticket.opened_at }
    [['resolution_sla_overrun_72h', config['basis'], overdue], ['age_at_close_72h', 'calendar', age]].map do |key, basis, values|
      observation(cohort, values).merge('key' => key, 'basis' => basis, 'observation_only' => true)
    end
  end

  private

  def completion_clock(close)
    cycle = close.payload.dig('sla', 'cycle_id')
    return unless cycle

    JrcServiceDesk::SlaClock.where(account: @context.account, ticket_id: close.ticket_id, sla_cycle_id: cycle, kind: 'resolution', state: 'completed')
                            .where('achieved_at <= ?', close.occurred_at).first
  end

  def observation(cohort, values)
    count = values.compact.count { |seconds| seconds > 72.hours }
    { 'numerator' => count, 'denominator' => cohort.size, 'value' => percentage(count, cohort, values),
      'unknown' => values.count(nil), 'samples' => cohort.zip(values).map { |close, seconds| sample(close, seconds) } }
  end

  def percentage(count, cohort, values)
    return if values.include?(nil) || cohort.empty?

    count * 100.0 / cohort.size
  end

  def sample(close, seconds)
    { 'closure_id' => close.id, 'cycle_id' => close.payload.dig('sla', 'cycle_id'), 'clock_id' => completion_clock(close)&.id,
      'elapsed_seconds' => seconds }
  end
end
