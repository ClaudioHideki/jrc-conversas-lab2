# Denominators are observed native cohorts. Missing evidence is not counted as success or displayed as zero.
class JrcNico::Helpdesk::Kpis
  TARGETS = { 'K1' => '>=15% phase 2', 'K2' => '<10%', 'K3' => '<10%', 'K4' => '100%',
              'K5' => '<=5min', 'K6' => '100% deliveries <=5min', 'K7' => '20%' }.freeze
  def initialize(member:, policy:, from:, until_at: Time.current, filters: {})
    @context = JrcNico::Helpdesk::Context.new(member)
    @policy = policy
    @from = from
    @until = until_at
    @filters = filters
    raise ArgumentError, 'Explicit bounded reporting interval required' unless @from <= @until && @until - @from <= 366.days
    raise Pundit::NotAuthorizedError unless policy.account_id == @context.account.id
  end

  def call
    @ids = JrcNico::Helpdesk::ReportingScope.new(@context, @policy, @filters).tickets.pluck(:id)
    { interval: { from: @from.iso8601(6), until: @until.iso8601(6), scope: 'authorized_pilot_tickets', policy_version: @policy.number },
      metrics: [autonomy, reopening, closed_overdue, prealert, latency('R01', 'n2', 'K5'), latency('R10', 'thiago', 'K6'), surveys] }
  end

  private

  def metric(key, numerator:, denominator:, reason: nil, extra: {})
    reason = observation_reason(key, denominator, reason)
    available = denominator.positive? && reason.nil?
    { key: key, state: available ? 'available' : 'sem_dados', numerator: available ? numerator : nil,
      denominator: denominator, value: available ? numerator * 100.0 / denominator : nil, unit: 'percent', target: TARGETS.fetch(key),
      reason: reason, evidence: extra }
      .merge(formula: formulas.fetch(key), window: { from: @from.iso8601(6), until: @until.iso8601(6) })
  end

  def observation_reason(key, denominator, reason)
    reason || permission_reason(key) || ('empty_observed_cohort' if denominator.zero?)
  end

  def permission_reason(key)
    'history_permission_required' if %w[K5 K6].exclude?(key) && !@context.native.capability?(:history_view)
  end

  def formulas
    { 'K1' => 'confirmed_autonomous_closures / observed_closures', 'K2' => 'reopens_within_14d / fully_observed_closure_cycles',
      'K3' => 'resolution_completions_overdue_72h / observed_closures', 'K4' => 'delivered_prealerts_before_deadline / expired_resolution_clocks',
      'K5' => 'reincidence_delivered_to_designated_n2_within_5m / detected_reincidence',
      'K6' => 'complaints_delivered_to_designated_recipient_within_5m / detected_complaints',
      'K7' => 'survey_dispatches_confirmed_sent / observed_closure_cycles' }
  end

  def closures
    return JrcServiceDesk::LifecycleTransition.none unless @context.native.capability?(:history_view)

    JrcServiceDesk::LifecycleTransition.where(account: @context.account, ticket_id: @ids, action: 'close', occurred_at: @from...@until)
  end

  def autonomy
    cohort = closures.to_a
    classes = cohort.map { |close| JrcNico::Helpdesk::NativeOrigin.new(close).classification }.tally
    coverage = { 'observed' => cohort.size, 'covered_human' => classes.fetch('covered_human', 0),
                 'human_approved_nico' => classes.fetch('human_approved_nico', 0), 'unknown' => classes.fetch('unknown', 0),
                 'autonomous_supported' => 0 }
    metric('K1', numerator: 0, denominator: cohort.size,
                 reason: coverage['unknown'].positive? ? 'incomplete_native_closure_origin' : nil,
                 extra: { 'coverage' => coverage, 'closure_ids' => cohort.map(&:id), 'excluded' => 'human_approved_tools_and_suggestions' })
  end

  def reopening
    defects = JrcNico::Helpdesk::TicketProfile.where(account: @context.account, ticket_id: @ids, case_kind: 'defect').select(:ticket_id)
    cohort = closures.where(ticket_id: defects).where('occurred_at <= ?', @until - 14.days).to_a
    count = cohort.count do |close|
      JrcServiceDesk::LifecycleTransition.where(account: @context.account, ticket_id: close.ticket_id, action: 'reopen')
                                         .exists?(['occurred_at > ? AND occurred_at <= ?', close.occurred_at, close.occurred_at + 14.days])
    end
    metric('K2', numerator: count, denominator: cohort.size,
                 extra: { 'closure_ids' => cohort.map(&:id), 'fully_observed_days' => 14, 'new_ticket_recurrence_is_separate' => true })
  end

  def closed_overdue
    config = @policy.definition.fetch('rules').fetch('R08')
    cohort = closures.to_a
    return metric('K3', numerator: 0, denominator: cohort.size, reason: 'sla_permission_required') unless @context.native.capability?(:sla_view)
    return unconfirmed_closure_metric(cohort, config) unless config['confirmed']

    observed_closure_metric(cohort, config)
  end

  def unconfirmed_closure_metric(cohort, config)
    observation_config = config.merge('basis' => 'calendar')
    values = cohort.map { |close| closure_evidence.overdue(close, observation_config) }
    metric('K3', numerator: 0, denominator: cohort.size,
                 reason: 'overdue_temporal_basis_not_confirmed',
                 extra: { 'source_conflict' => { 'code' => 'C10', 'resolved' => false },
                          'observations' => closure_evidence.observations(cohort, values, observation_config) })
  end

  def observed_closure_metric(cohort, config)
    values = cohort.map { |close| closure_evidence.overdue(close, config) }
    missing = values.count(nil)
    metric('K3', numerator: values.compact.count { |seconds| seconds > 72.hours }, denominator: cohort.size,
                 reason: missing.positive? ? 'incomplete_resolution_clock_provenance' : nil,
                 extra: { 'basis' => config['basis'], 'unknown' => missing, 'clock' => 'native_resolution_completion',
                          'source_conflict' => { 'code' => 'C10', 'resolved' => false },
                          'observations' => closure_evidence.observations(cohort, values, config) })
  end

  def closure_evidence
    @closure_evidence ||= JrcNico::Helpdesk::KpiClosureEvidence.new(@context)
  end

  def prealert
    return metric('K4', numerator: 0, denominator: 0, reason: 'sla_permission_required') unless @context.native.capability?(:sla_view)

    clocks = JrcServiceDesk::SlaClock.where(account: @context.account, ticket_id: @ids, kind: 'resolution', due_at: @from...@until)
                                     .where('due_at <= ?', [@until, Time.current].min)
                                     .where("state = 'running' OR (state = 'completed' AND achieved_at > due_at)").to_a
    matched = clocks.count { |clock| prealert_delivered?(clock) }
    metric('K4', numerator: matched, denominator: clocks.size,
                 extra: { 'clock_ids' => clocks.map(&:id), 'queued_is_delivery' => false })
  end

  def prealert_delivered?(clock)
    events = JrcNico::Helpdesk::Event.where(account: @context.account, ticket_id: clock.ticket_id, rule_key: 'R05')
                                     .where("evidence ->> 'clock_id' = ?", clock.id.to_s)
    events.any? do |event|
      next false unless visible?(event)

      ids = event.policy_version.definition.dig('rules', 'R05', 'recipients')
      JrcNico::Helpdesk::DeliveryReceipt.where(account: @context.account, source_type: 'event', source_id: event.id,
                                               recipient_id: ids, state: 'delivered').exists?(['delivered_at < ?', clock.due_at])
    end
  end

  def latency(rule, role, key)
    ids = @policy.definition.fetch('roles').fetch(role) & @policy.definition.fetch('rules').fetch(rule).fetch('recipients')
    events = JrcNico::Helpdesk::Event.where(account: @context.account, ticket_id: @ids, rule_key: rule, detected_at: @from...@until)
                                     .select { |event| visible?(event) }
    return metric(key, numerator: 0, denominator: events.size, reason: 'designated_recipient_role_required') if ids.empty?

    evidence = JrcNico::Helpdesk::KpiLatencyEvidence.new(@context)
    durations = events.filter_map { |event| evidence.sample(event, ids)&.fetch('elapsed_seconds') }
    metric(key, numerator: durations.count { |seconds| seconds.between?(0, 300) }, denominator: events.size,
                extra: evidence.call(role, events, durations, ids))
  end

  def visible?(event)
    @context.event(event.id)
    true
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    false
  end

  def surveys
    cohort = closures.to_a
    evidence = JrcNico::Helpdesk::KpiSurveyEvidence.new(@context, @until).call(cohort)
    metric('K7', numerator: evidence.fetch('sent'), denominator: cohort.size, extra: evidence)
  rescue Pundit::NotAuthorizedError
    metric('K7', numerator: 0, denominator: 0, reason: 'survey_permission_required')
  end
end
