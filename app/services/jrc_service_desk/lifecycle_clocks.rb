# frozen_string_literal: true

# Invoked only inside LifecycleTransitionService's authorized unit/ticket transaction.
class JrcServiceDesk::LifecycleClocks
  def initialize(ticket:, version:, actor:, now:)
    @ticket, @version, @actor, @now = ticket, version, actor, now
    @settings = version.definition.fetch('sla')
  end

  def run!(rule:, reason:, reopening:)
    pause = @ticket.lifecycle_pauses.find_by(ended_at: nil)
    if rule['action'] == 'pause'
      raise ArgumentError, 'Ticket already paused' if pause
    elsif rule['action'] == 'resume'
      raise ArgumentError, 'No recorded pause to resume' unless pause
    elsif pause && !rule['end_pause']
      raise ArgumentError, 'Policy must explicitly end the current pause'
    end

    if @settings['mode'] == 'not_applicable'
      raise JrcServiceDesk::LifecycleDependencyError, 'Existing SLA cycle conflicts with non-applicable policy' if @ticket.sla_cycles.exists?
      close_pause!(pause) if pause && rule['action'] != 'pause'
      create_pause!(reason, nil) if rule['action'] == 'pause'
      return { 'mode' => 'not_applicable', 'cycle_id' => nil, 'reopening' => reopening, 'clocks' => [] }
    end

    cycle = @ticket.sla_cycles.order(number: :desc).first
    if reopening && !cycle
      raise JrcServiceDesk::LifecycleDependencyError, 'Reopening requires the historical SLA cycle; no cycle was fabricated'
    end
    cycle ||= create_cycle!(@ticket.latest_sla_snapshot, @ticket.opened_at)
    previous_cycle = nil
    if reopening && reopening['sla_cycle'] == 'new_cycle'
      # Preserve old clock state as historical; unfinished clocks stop at the boundary.
      previous_cycle = { 'id' => cycle.id, 'number' => cycle.number, 'clocks' => projection(cycle.sla_clocks.order(:kind).to_a) }
      prior_calendar = calendar(cycle)
      cycle.sla_clocks.each do |clock|
        settle!(clock, prior_calendar)
        clock.update!(state: 'stopped', achieved_at: nil, anchor_at: @now) if %w[running paused].include?(clock.state)
      end
      close_pause!(pause) if pause
      snapshot = reopening['new_cycle_snapshot'] == 'latest_snapshot' ? @ticket.latest_sla_snapshot : cycle.sla_snapshot
      cycle = create_cycle!(snapshot, @now)
      pause = nil
    end
    cal = calendar(cycle)
    clocks = cycle.sla_clocks.order(:kind).to_a
    expected_kinds = cycle.lifecycle_policy_version.rules.clock_kinds
    raise JrcServiceDesk::LifecycleDependencyError, 'SLA cycle clocks are incomplete' unless clocks.map(&:kind).sort == expected_kinds.sort
    before = projection(clocks)
    clocks.each { |clock| settle!(clock, cal) }

    if reopening && reopening['sla_cycle'] == 'continue_cycle'
      clocks.each do |clock|
        next unless reopening.fetch('resume_clocks').include?(clock.kind)
        if reopening['inactive_time'] == 'count' && clock.state != 'running'
          clock.elapsed_seconds += cal.elapsed(clock.anchor_at, @now)
        end
        clock.state = 'running'; clock.achieved_at = nil; clock.anchor_at = @now
        recalculate!(clock, cal)
        clock.save!
      end
    end
    if pause && rule['action'] != 'pause'
      raise JrcServiceDesk::LifecycleDependencyError, 'Pause belongs to another SLA cycle' if pause.sla_cycle_id && pause.sla_cycle_id != cycle.id
      clocks.each do |clock|
        next unless pause.clocks.include?(clock.kind) && clock.state == 'paused'
        clock.state = 'running'; clock.anchor_at = @now
        recalculate!(clock, cal); clock.save!
      end
      close_pause!(pause)
    end
    if rule['action'] == 'pause'
      clocks.each do |clock|
        next unless reason.fetch('clocks').include?(clock.kind)
        raise ArgumentError, 'Only a running clock can be paused' unless clock.state == 'running'
        clock.update!(state: 'paused', anchor_at: @now)
      end
      create_pause!(reason, cycle)
    else
      clocks.each do |clock|
        effect = rule.fetch('clocks').fetch(clock.kind)
        next if effect == 'keep'
        # No inferred first response; policy validator excludes that effect.
        if effect == 'complete'
          raise ArgumentError, 'A stopped clock cannot be marked complete' if clock.state == 'stopped'
          clock.update!(state: 'completed', achieved_at: @now, anchor_at: @now) unless clock.state == 'completed'
        elsif effect == 'stop' && !%w[completed stopped].include?(clock.state)
          clock.update!(state: 'stopped', achieved_at: nil, anchor_at: @now)
        end
      end
    end
    { 'mode' => 'calendar_snapshot', 'cycle_id' => cycle.id, 'cycle_number' => cycle.number,
      'snapshot_id' => cycle.sla_snapshot_id, 'snapshot_version' => cycle.sla_snapshot.version,
      'calculator_version' => JrcServiceDesk::SnapshotCalendar::VERSION, 'reopening' => reopening,
      'previous_cycle' => previous_cycle, 'before' => before, 'clocks' => projection(clocks.map(&:reload)) }
  end

  def self.verify_snapshot!(snapshot, clock_kinds: nil)
    raise JrcServiceDesk::LifecycleDependencyError, 'SLA/calendar snapshot is required' unless snapshot
    targets = snapshot.policy_conditions['clock_budgets_seconds']
    kinds = clock_kinds || (targets.is_a?(Hash) && targets.key?('attendance') ? JrcServiceDesk::LifecycleRules::ATTENDANCE_CLOCKS : JrcServiceDesk::LifecycleRules::CLOCKS)
    unless targets.is_a?(Hash) && targets.keys.sort == kinds.sort &&
           targets.values.all? { |n| n.is_a?(Integer) && n.positive? && n <= 2**53 - 1 }
      raise JrcServiceDesk::LifecycleDependencyError, 'Explicit budgets matching the published clock policy are required in the snapshot'
    end
    JrcServiceDesk::SnapshotCalendar.new(timezone: snapshot.timezone, conditions: snapshot.calendar_conditions)
  end

  private

  def calendar(cycle)
    self.class.verify_snapshot!(cycle.sla_snapshot, clock_kinds: cycle.lifecycle_policy_version.rules.clock_kinds)
  end

  def create_cycle!(snapshot, start)
    cal = self.class.verify_snapshot!(snapshot, clock_kinds: @version.rules.clock_kinds)
    raise ArgumentError, 'Snapshot or start is outside this ticket' unless snapshot.ticket_id == @ticket.id && snapshot.account_id == @ticket.account_id && snapshot.unit_id == @ticket.unit_id && start <= @now
    cycle = @ticket.sla_cycles.create!(account: @ticket.account, unit: @ticket.unit, lifecycle_policy_version: @version,
      sla_snapshot: snapshot, number: (@ticket.sla_cycles.maximum(:number) || 0) + 1, started_at: start)
    snapshot.policy_conditions.fetch('clock_budgets_seconds').each do |kind, budget|
      cycle.sla_clocks.create!(account: @ticket.account, unit: @ticket.unit, ticket: @ticket, kind: kind,
        state: 'running', budget_seconds: budget, elapsed_seconds: 0, anchor_at: start,
        due_at: cal.advance(start, budget), calculator_version: JrcServiceDesk::SnapshotCalendar::VERSION)
    end
    cycle
  end

  def settle!(clock, cal)
    return unless clock.state == 'running'
    clock.elapsed_seconds += cal.elapsed(clock.anchor_at, @now)
    clock.anchor_at = @now
    clock.save!
  end

  def recalculate!(clock, cal)
    remaining = clock.budget_seconds - clock.elapsed_seconds.to_f
    # An already exhausted clock retains its real previous deadline, never "now".
    clock.due_at = cal.advance(@now, remaining) if remaining.positive?
  end

  def create_pause!(reason, cycle)
    @ticket.lifecycle_pauses.create!(account: @ticket.account, unit: @ticket.unit, lifecycle_policy_version: @version,
      sla_cycle: cycle, reason_code: reason.fetch('code'), clocks: reason.fetch('clocks'),
      started_at: @now, started_by_membership: @actor)
  end

  def close_pause!(pause)
    pause&.update!(ended_at: @now, ended_by_membership: @actor)
  end

  def projection(clocks)
    clocks.map do |clock|
      { 'id' => clock.id, 'kind' => clock.kind, 'state' => clock.state, 'budget_seconds' => clock.budget_seconds,
        'elapsed_seconds' => clock.elapsed_seconds.to_f, 'anchor_at' => clock.anchor_at.iso8601(6),
        'due_at' => clock.due_at.iso8601(6), 'achieved_at' => clock.achieved_at&.iso8601(6), 'met' => clock.met? }
    end
  end
end
