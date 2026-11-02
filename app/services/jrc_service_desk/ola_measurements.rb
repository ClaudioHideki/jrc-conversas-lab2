# frozen_string_literal: true

# Uses the native OlaClock and SnapshotCalendar. Queue-entry snapshots freeze
# all internal targets; policy publication does not remeasure existing tickets.
module JrcServiceDesk::OlaMeasurements
  module_function

  def sync!(ticket, now:)
    active = ticket.ola_clocks.where(state: %w[running paused]).lock.order(:id).to_a
    active.each { |clock| settle!(clock, ticket, now) }
    current = active.select { |clock| %w[running paused].include?(clock.state) }
    return current.first if current.any?
    return unless %w[open waiting].include?(ticket.status.phase)

    queue = ticket.queue
    return JrcServiceDesk::OlaTracker.sync!(ticket, now: now) if queue && queue.ola_targets.blank?
    return unless queue&.ola_targets.present?

    last = ticket.ola_clocks.order(id: :desc).first
    reopening = ticket.lifecycle_transitions.where(action: 'reopen').maximum(:occurred_at)
    return last if last && last.queue_id == queue.id && last.kind != 'queue_residence' &&
                   (!reopening || reopening <= last.started_at)

    publication = queue.current_policy_version
    raise JrcServiceDesk::LifecycleDependencyError, 'Publish the queue before starting independent OLA clocks' unless publication

    entry = SecureRandom.uuid
    queue.ola_targets.each do |kind, budget|
      ticket.ola_clocks.create!(attributes(ticket, queue, publication, kind, budget, entry, now))
    end
    ticket.ola_clocks.order(id: :desc).first
  end

  def attributes(ticket, queue, publication, kind, budget, entry, now)
    calendar = queue.ola_time_basis == 'business' ? queue.ola_calendar.deep_dup : {}
    cal = calendar_for(calendar)
    { account: ticket.account, unit: ticket.unit, queue: queue, queue_policy_version: publication,
      kind: kind, entry_key: entry, calendar_snapshot: calendar, budget_seconds: budget,
      time_basis: queue.ola_time_basis, pause_waiting: queue.ola_pause_waiting,
      escalation_snapshot: queue.ola_escalation_policy.deep_dup, policy_revision: publication.digest,
      state: queue.ola_pause_waiting && ticket.status.phase == 'waiting' ? 'paused' : 'running',
      started_at: now, anchor_at: now, due_at: cal ? cal.advance(now, budget) : now + budget }
  end

  def calendar_for(snapshot)
    return if snapshot.blank?

    JrcServiceDesk::SnapshotCalendar.new(timezone: snapshot.fetch('timezone'), conditions: snapshot.fetch('conditions'))
  end

  def settle!(clock, ticket, now)
    cal = if clock.calendar_snapshot.present?
            calendar_for(clock.calendar_snapshot)
          else
            (clock.time_basis == 'business' ? JrcServiceDesk::OlaTracker.calendar_for(clock.sla_snapshot) : nil)
          end
    now = [now, clock.anchor_at].max
    clock.elapsed_seconds += cal ? cal.elapsed(clock.anchor_at, now) : now - clock.anchor_at if clock.state == 'running'
    clock.anchor_at = now
    if clock.queue_id != ticket.queue_id || !%w[open waiting].include?(ticket.status.phase)
      achieved = clock.queue_id == ticket.queue_id && %w[resolved closed].include?(ticket.status.phase) &&
                 %w[resolution queue_residence].include?(clock.kind)
      clock.state = achieved ? 'completed' : 'stopped'
      clock.ended_at = now
    elsif clock.pause_waiting && ticket.status.phase == 'waiting'
      clock.state = 'paused'
    else
      remaining = clock.budget_seconds - clock.elapsed_seconds
      clock.due_at = cal ? cal.advance(now, remaining) : now + remaining if clock.state == 'paused' && remaining.positive?
      clock.state = 'running'
    end
    clock.save!
  end

  # Only accepted native public reply evidence invokes this method. A note,
  # assignment or queue entry is not a first response. Repeated receipts do not
  # advance the update measurement a second time.
  def response!(ticket, message:, at:)
    return if ticket.ticket_events.where(event_type: 'resource_updated').exists?(['data @> ?::jsonb',
                                                                                  { 'ola_response_message_id' => message.id }.to_json])

    clocks = ticket.ola_clocks.where(queue_id: ticket.queue_id, kind: %w[first_response update], state: %w[running paused]).lock.to_a
    clocks.each do |clock|
      next if at < clock.anchor_at

      cal = calendar_for(clock.calendar_snapshot)
      clock.elapsed_seconds += cal ? cal.elapsed(clock.anchor_at, at) : at - clock.anchor_at if clock.state == 'running'
      clock.update!(state: 'completed', anchor_at: at, ended_at: at)
      next unless clock.kind == 'update' && %w[open waiting].include?(ticket.status.phase)

      attrs = clock.attributes.except('id', 'created_at', 'updated_at', 'elapsed_seconds', 'ended_at')
      attrs.merge!('state' => clock.pause_waiting && ticket.status.phase == 'waiting' ? 'paused' : 'running',
                   'started_at' => at, 'anchor_at' => at, 'due_at' => cal ? cal.advance(at, clock.budget_seconds) : at + clock.budget_seconds)
      ticket.ola_clocks.create!(attrs)
    end
    clocks.any?
  end
end
