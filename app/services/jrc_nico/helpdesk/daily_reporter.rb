class JrcNico::Helpdesk::DailyReporter
  def initialize(policy, now: Time.current, filters: {})
    @policy = policy
    @now = now
    @filters = filters
  end

  def call
    settings = @policy.definition.fetch('daily')
    return [] unless @policy.published? && @policy.enabled? && settings.fetch('enabled')

    local = TZInfo::Timezone.get(settings.fetch('timezone')).to_local(@now)
    return [] if local.hour < settings.fetch('hour')

    settings.fetch('recipients').filter_map { |id| report_for(id, local.to_date, settings) }
  end

  def preview(member:)
    context = JrcNico::Helpdesk::Context.new(member)
    raise Pundit::NotAuthorizedError unless context.account.id == @policy.account_id

    settings = @policy.definition.fetch('daily')
    date = TZInfo::Timezone.get(settings.fetch('timezone')).to_local(@now).to_date
    tickets = JrcNico::Helpdesk::ReportingScope.new(context, @policy, @filters).tickets.to_a
    payload(context, tickets, date, settings).merge('preview' => true, 'persisted' => false, 'delivery' => 'not_requested')
  end

  private

  def report_for(id, date, settings)
    member = @policy.account.account_users.find_by(id: id)
    return unless member

    report = build(member, date, settings)
    settings.fetch('channels').each { |channel| JrcNico::Helpdesk::Delivery.new(source: report, recipient: member, channel: channel).call }
    report
  rescue Pundit::NotAuthorizedError
    nil
  end

  def build(member, date, settings)
    context = JrcNico::Helpdesk::Context.new(member)
    reporting = JrcNico::Helpdesk::ReportingScope.new(context, @policy, @filters)
    tickets = reporting.tickets.to_a
    digest = reporting.digest
    @policy.account.with_lock do
      scope = JrcNico::Helpdesk::DailyReport.where(account: @policy.account, recipient: member, report_date: date)
      # One recipient/scope version per date; growing backlog is not a second daily dispatch.
      existing = scope.find_by(scope_digest: digest)
      next existing if existing

      scope.create!(policy_version: @policy, scope_digest: digest, timezone: settings.fetch('timezone'), cutoff_at: @now,
                    payload: payload(context, tickets, date, settings))
    end
  end

  def payload(context, tickets, date, settings)
    window = JrcNico::Helpdesk::ReportWindow.new(settings.fetch('timezone'), @now)
    details = tickets.filter_map { |ticket| overdue_detail(context, ticket) }
    events = visible_events(context, tickets.map(&:id))
    report_metadata(context, tickets, settings, window)
      .merge(event_windows(events, window)).merge(overdue_payload(details, date, settings)).merge(event_payload(events)).tap do |value|
        value['autonomy'] = value.fetch('kpis')[:metrics].find { |metric| metric[:key] == 'K1' }.stringify_keys
        value['evidence_resources'] = JrcNico::Helpdesk::ReportResources.new(context, value).call
      end
  end

  def report_metadata(context, tickets, settings, window)
    { 'ticket_ids' => tickets.map(&:id).sort, 'scheduled_hour' => settings.fetch('hour'), 'cutoff_at' => @now.iso8601(6),
      'timezone' => settings.fetch('timezone'), 'window' => window.to_h, 'filters' => @filters.stringify_keys,
      'kpis' => JrcNico::Helpdesk::Kpis.new(member: context.member, policy: @policy, from: window.from, until_at: @now, filters: @filters).call }
  end

  def visible_events(context, ticket_ids)
    JrcNico::Helpdesk::Event.where(account: @policy.account, ticket_id: ticket_ids).where('detected_at < ?', @now)
                            .select { |event| visible?(context, event) }
  end

  def event_windows(events, window)
    { 'new_event_ids' => events.select { |event| event.detected_at >= window.from }.map(&:id),
      'previous_event_ids' => events.select { |event| event.detected_at < window.from }.map(&:id) }
  end

  def overdue_payload(details, date, settings)
    { 'overdue' => details, 'new_overdue_today' => details.select { |item| local_date(item['due_at'], settings) == date },
      'previous_backlog' => details.select { |item| local_date(item['due_at'], settings) < date } }
  end

  def event_payload(events)
    { 'visible_event_ids' => events.map(&:id), 'complaints' => event_tickets(events, 'R10'),
      'legal_risk_internal_only' => event_tickets(events, 'R11'), 'recurrent' => event_tickets(events, 'R01'),
      'root_cause_events' => event_ids(events, %w[R02 R03]), 'mass_events' => event_ids(events, ['R04']),
      'escalations' => escalations(events) }
  end

  def event_ids(events, rules)
    events.select { |event| rules.include?(event.rule_key) }.map(&:id)
  end

  def escalations(events)
    events.group_by { |event| [event.rule_key, event.state] }
          .map { |(rule, state), rows| { 'rule' => rule, 'state' => state, 'count' => rows.size } }
  end

  def event_tickets(events, rule)
    events.select { |event| event.rule_key == rule }.map(&:ticket_id).uniq
  end

  def visible?(context, event)
    context.event(event.id)
    true
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    false
  end

  def local_date(value, settings)
    TZInfo::Timezone.get(settings.fetch('timezone')).to_local(Time.iso8601(value)).to_date
  end

  def overdue_detail(context, ticket)
    Pundit.authorize(context.native.to_h, ticket, :view_sla?)
    facts = JrcNico::Helpdesk::Facts.new(context: context, policy: @policy, ticket: ticket, trigger: 'monitor', now: @now).call
    return unless facts['sla_running'] && facts['overdue_calendar_seconds']&.positive?

    { 'ticket_id' => ticket.id, 'company_id' => ticket.company_id, 'service_id' => ticket.service_id, 'case_kind' => facts['case_kind'],
      'assignee_account_user_id' => ticket.assignee_account_user&.id, 'status_id' => ticket.status_id, 'unit_id' => ticket.unit_id,
      'due_at' => facts.fetch('due_at'), 'budget_seconds' => facts.fetch('sla_budget_seconds'),
      'overdue_calendar_seconds' => facts.fetch('overdue_calendar_seconds'), 'overdue_business_seconds' => facts.fetch('overdue_business_seconds'),
      'escalation_event_ids' => escalation_event_ids(context, ticket) }
  rescue Pundit::NotAuthorizedError
    nil
  end

  def escalation_event_ids(context, ticket)
    JrcNico::Helpdesk::Event.where(account: @policy.account, ticket: ticket, rule_key: %w[R06 R07 R08 R09])
                            .select { |event| visible?(context, event) }.map(&:id)
  end
end
