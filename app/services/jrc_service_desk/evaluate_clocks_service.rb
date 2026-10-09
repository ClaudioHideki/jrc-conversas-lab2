# frozen_string_literal: true

# Explicit authorized command. OFF creates no history or backlog; GET never calls it.
class JrcServiceDesk::EvaluateClocksService < JrcServiceDesk::BaseService
  def call(ticket_id:)
    with_ticket(ticket_id, :update?) do |ticket|
      authorize!(ticket, :view_sla?)
      evaluate_sla!(ticket)
      evaluate_ola!(ticket)
      ticket
    end
  end

  def evaluate_clock(kind:, clock_id:, policy_digest:)
    model = { 'sla' => JrcServiceDesk::SlaClock, 'ola' => JrcServiceDesk::OlaClock }.fetch(kind)
    initial = fresh_context!
    candidate = model.where(account_id: initial.account.id).find(JrcServiceDesk::Input.id(clock_id))
    with_ticket(candidate.ticket_id, :update?) do |ticket|
      authorize!(ticket, :view_sla?)
      clock = model.where(account_id: context.account.id, unit_id: ticket.unit_id, ticket_id: ticket.id).lock.find(candidate.id)
      binding = JrcServiceDesk::ClockMonitoringBinding.new(clock)
      binding.verify!(expected_digest: policy_digest, execution_account_user_id: context.account_user.id)
      evaluate!(ticket, clock, binding.policy, binding.digest)
      ticket
    end
  end

  private

  def evaluate_sla!(ticket)
    version = JrcServiceDesk::LifecycleSelector.new(ticket).applicable
    cycle = ticket.sla_cycles.order(number: :desc).first
    return unless version && cycle

    policy = JrcServiceDesk::ClockEscalationPolicy.new(version.definition.dig('sla', 'escalation_policy') || {})
    cycle.sla_clocks.lock.order(:kind).each { |clock| evaluate!(ticket, clock, policy, version.digest) }
  end

  def evaluate_ola!(ticket)
    ticket.ola_clocks.where(state: %w[running paused completed]).lock.order(:id).each do |clock|
      policy = JrcServiceDesk::ClockEscalationPolicy.new(clock.escalation_snapshot)
      evaluate!(ticket, clock, policy, clock.policy_revision)
    end
  end

  def evaluate!(ticket, clock, policy, digest)
    return unless policy.enabled?

    observation = JrcServiceDesk::ClockProjection.new(clock).call
    record_violation!(ticket, clock, observation, digest) if observation[:breached]
    policy.thresholds.each do |threshold|
      next unless threshold_reached?(ticket, clock, threshold, observation, digest)

      record_threshold!(ticket, clock, threshold, observation, digest)
    end
  end

  def record_violation!(ticket, clock, observation, digest)
    proof = { 'clock_id' => clock.id, 'clock_kind' => observation[:kind], 'policy_digest' => digest }
    return if ticket.ticket_events.where(event_type: 'clock_violated').exists?(['data @> ?::jsonb', proof.to_json])

    fields = observation.slice(:elapsed_seconds, :budget_seconds, :due_at, :observed_at).stringify_keys
    append_event!(ticket, 'clock_violated', proof.merge(fields))
  end

  def threshold_reached?(ticket, clock, threshold, observation, digest)
    observation[:consumed_percent] >= threshold['percent'] && !already_recorded?(ticket, clock, threshold, digest)
  end

  def record_threshold!(ticket, clock, threshold, observation, digest)
    escalate!(ticket, threshold) if threshold['queue_id'] && clock.state == 'running'
    fields = observation.slice(:elapsed_seconds, :budget_seconds, :due_at, :breached).stringify_keys
    proof = { 'clock_id' => clock.id, 'clock_kind' => observation[:kind], 'percent' => threshold['percent'],
              'policy_digest' => digest, 'target_queue_id' => threshold['queue_id'] }
    append_event!(ticket, 'clock_threshold_reached', proof.merge(fields))
  end

  def already_recorded?(ticket, clock, threshold, digest)
    proof = { clock_id: clock.id, clock_kind: clock.respond_to?(:kind) ? clock.kind : 'ola',
              percent: threshold['percent'], policy_digest: digest }
    ticket.ticket_events.where(event_type: 'clock_threshold_reached').exists?(['data @> ?::jsonb', proof.to_json])
  end

  def escalate!(ticket, threshold)
    authorize!(ticket, :transfer?)
    queue = reference(JrcServiceDesk::Queue, threshold['queue_id'], ticket.unit)
    raise ArgumentError, 'Escalation team does not match the approved queue' if threshold['team_id'] && queue.team_id != threshold['team_id']

    JrcServiceDesk::TransferTicketService.new(user_context: context.to_h).call(
      ticket_id: ticket.id, attributes: { queue_id: queue.id, team_id: queue.team_id, assignee_account_user_id: nil },
      expected_lock_version: ticket.lock_version
    )
    ticket.reload
  end
end
