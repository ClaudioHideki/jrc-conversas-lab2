# The human presenter remains unchanged. NICO checks the selected source before
# clock/calendar interpretation and retains those exact IDs for saved results.
class JrcNico::ServiceDeskPresenter < JrcServiceDesk::Presenter
  def initialize(user_context:)
    super
    @evidence = JrcNico::SlaEvidence.new(user_context.fetch(:account))
    @sla_resources = {}
  end

  def sla_resources(ticket)
    @sla_resources.fetch(ticket.id, [])
  end

  private

  def sla_summary(ticket)
    @sla_resources[ticket.id] = []
    cycle = ticket.sla_cycles.order(number: :desc).first
    return cycle_summary(ticket, cycle) if cycle

    snapshot = ticket.latest_sla_snapshot
    unless snapshot
      @sla_resources[ticket.id] = [['JrcNico::ServiceTicketSla', ticket.id]]
      return { state: 'unavailable', first_response_due_at: nil, resolution_due_at: nil }
    end

    milestone_summary(ticket, snapshot)
  rescue ActiveRecord::RecordNotFound
    @sla_resources[ticket.id] = []
    nil
  end

  def milestone_summary(ticket, snapshot)
    @evidence.snapshot!(snapshot)
    milestones = snapshot.sla_milestones.to_a
    milestones.each { |milestone| @evidence.milestone!(milestone) }
    @sla_resources[ticket.id] = [[JrcNico::SlaEvidence::SNAPSHOT_RESOURCE, snapshot.id]] +
                                milestones.map { |milestone| [JrcNico::SlaEvidence::MILESTONE_RESOURCE, milestone.id] }
    { state: milestones.length == 2 && milestones.none?(&:calculation_pending?) ? 'calculated' : 'pending',
      first_response_due_at: due_at(milestones, 'first_response'), resolution_due_at: due_at(milestones, 'resolution') }
  end

  def cycle_summary(ticket, cycle)
    snapshot = @evidence.snapshot!(cycle.sla_snapshot)
    clocks = cycle.sla_clocks.to_a
    projections = clocks.map { |clock| JrcServiceDesk::ClockProjection.new(clock).call }
    @sla_resources[ticket.id] = [[JrcNico::SlaEvidence::SNAPSHOT_RESOURCE, snapshot.id]]
    { state: clock_state(projections), first_response_due_at: due_at(clocks, 'first_response'),
      resolution_due_at: due_at(clocks, 'resolution'), attendance_due_at: due_at(clocks, 'attendance'), clocks: projections }
  end

  def due_at(records, kind)
    stamp(records.find { |row| row.kind == kind }&.due_at)
  end

  def clock_state(projections)
    states = projections.pluck(:deadline_state)
    %w[overdue paused near_due on_time completed stopped].find { |value| states.include?(value) } || 'unavailable'
  end
end
