# frozen_string_literal: true

# Internal team clock; never rewrites customer SLA budgets, snapshots or deadlines.
# Runs inside authorized ticket commands and retains every previous queue interval.
class JrcServiceDesk::OlaTracker
  def self.current_revision(queue, snapshot)
    policy_revision(queue, snapshot)
  end

  def self.sync!(ticket, now: Time.current)
    active = ticket.ola_clocks.lock.find_by(state: %w[running paused])
    if active
      update_current!(active, ticket, now)
      return active if %w[running paused].include?(active.state)
    end
    queue = ticket.queue
    return unless queue&.ola_budget_seconds && %w[open waiting].include?(ticket.status.phase)

    snapshot, calendar = creation_calendar(ticket, queue)
    ticket.ola_clocks.create!(clock_attributes(ticket, queue, snapshot, calendar, now))
  end

  def self.update_current!(active, ticket, now)
    calendar = calendar_for(active.sla_snapshot) if active.time_basis == 'business'
    active.elapsed_seconds += elapsed(active, calendar, now)
    active.anchor_at = now
    if active.queue_id != ticket.queue_id || %w[open waiting].exclude?(ticket.status.phase)
      active.state = %w[resolved closed].include?(ticket.status.phase) ? 'completed' : 'stopped'
      active.ended_at = now
    elsif active.pause_waiting && ticket.status.phase == 'waiting'
      active.state = 'paused'
    else
      resume_clock(active, calendar, now)
    end
    active.save!
  end
  private_class_method :update_current!

  def self.elapsed(active, calendar, now)
    return 0 unless active.state == 'running'

    calendar ? calendar.elapsed(active.anchor_at, now) : now - active.anchor_at
  end
  private_class_method :elapsed

  def self.resume_clock(active, calendar, now)
    remaining = active.budget_seconds - active.elapsed_seconds
    active.due_at = due_at(calendar, now, remaining) if active.state == 'paused' && remaining.positive?
    active.state = 'running'
  end
  private_class_method :resume_clock

  def self.creation_calendar(ticket, queue)
    raise JrcServiceDesk::LifecycleDependencyError, 'Explicit OLA time basis required' unless %w[calendar business].include?(queue.ola_time_basis)
    return [nil, nil] unless queue.ola_time_basis == 'business'

    snapshot = ticket.latest_sla_snapshot
    raise JrcServiceDesk::LifecycleDependencyError, 'Business OLA requires an explicit calendar snapshot' unless snapshot

    [snapshot, calendar_for(snapshot)]
  end
  private_class_method :creation_calendar

  def self.calendar_for(snapshot)
    JrcServiceDesk::SnapshotCalendar.new(timezone: snapshot.timezone, conditions: snapshot.calendar_conditions)
  end
  private_class_method :calendar_for

  def self.due_at(calendar, now, budget)
    calendar ? calendar.advance(now, budget) : now + budget
  end
  private_class_method :due_at

  def self.clock_attributes(ticket, queue, snapshot, calendar, now)
    { account: ticket.account, unit: ticket.unit, queue: queue, sla_snapshot: snapshot,
      budget_seconds: queue.ola_budget_seconds, time_basis: queue.ola_time_basis, pause_waiting: queue.ola_pause_waiting,
      escalation_snapshot: JrcServiceDesk::ClockEscalationPolicy.new(queue.ola_escalation_policy).definition,
      policy_revision: policy_revision(queue, snapshot), state: queue.ola_pause_waiting && ticket.status.phase == 'waiting' ? 'paused' : 'running',
      started_at: now, anchor_at: now, due_at: due_at(calendar, now, queue.ola_budget_seconds) }
  end
  private_class_method :clock_attributes

  def self.policy_revision(queue, snapshot)
    JrcServiceDesk::CanonicalJson.digest('queue_id' => queue.id, 'budget' => queue.ola_budget_seconds,
                                         'basis' => queue.ola_time_basis, 'pause_waiting' => queue.ola_pause_waiting,
                                         'escalation_policy' => queue.ola_escalation_policy, 'snapshot_id' => snapshot&.id)
  end
  private_class_method :policy_revision
end
