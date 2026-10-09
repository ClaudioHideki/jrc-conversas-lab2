class JrcRelationship::Presenter
  def initialize(context)
    @context = context
  end

  def assignment(record, signals: nil)
    snapshot = snapshots[record.id]
    signals ||= snapshot&.signals&.deep_symbolize_keys || { health: { score: nil, band: 'unavailable', factors: [] } }
    next_action = next_actions[record.id]
    { id: record.id, name: record.label, company_id: record.company_id, contact_id: record.contact_id,
      business_unit_id: record.business_unit_id, business_unit: record.business_unit&.name,
      owner: record.owner && { id: record.owner.id, name: record.owner.name }, team_id: record.team_id,
      status: record.status, settings: record.settings, signals: signals.except(:_source_ids),
      calculated_at: snapshot&.calculated_at,
      next_action: next_action && { id: next_action.id, reason: next_action.reason, status: next_action.status, due_at: next_action.due_at },
      expansion_potential_cents: (@expansions || {}).fetch(record.id, nil),
      risks: (@risks || {}).fetch(record.id, []),
      customer_360: JrcRelationship::RecordPresentation.customer_route(record) }
  end

  def record(record)
    attrs = record.attributes.except('token_digest', 'account_id')
    attrs['metadata'] = attrs['metadata'].except('_source_ids') if attrs['metadata'].is_a?(Hash)
    attrs['sla'] = JrcOperations::SlaClock.new(record).snapshot if record.is_a?(JrcRelationship::Action)
    attrs['source_links'] = JrcRelationship::ActionSources.new(@context, record).call if record.is_a?(JrcRelationship::Action)
    projection = JrcRelationship::RecordPresentation.new(@context, snapshot: ->(id) {
      snapshots[id]
    }, risk_actions: @risk_actions || {}, risks: @risks || {})
    projection.augment!(attrs, record)
    attrs.merge('customer_name' => projection.customer_name(record), 'owner_name' => record.owner&.name)
  end

  def dashboard(scope, period: nil)
    ids = scope.select(:id)
    snapshots = JrcRelationship::HealthSnapshot.where(account_id: @context.account.id, viewer_id: @context.user.id, assignment_id: ids,
                                                      access_signature: @context.access_signature)
    snapshots = JrcRelationship::SnapshotAccess.scope(@context, snapshots)
    latest_ids = snapshots.select('MAX(id) AS id').group(:assignment_id)
    health = snapshots.where(id: latest_ids)
    customer = scope.pluck(:company_id, :contact_id)
    contact_ids = @context.account.contacts.where(company_id: customer.filter_map(&:first)).pluck(:id) + customer.filter_map(&:last)
    visibility = JrcCustomers::Visibility.new(account: @context.account, user: @context.user, account_user: @context.member)
    deals = visibility.crm(@context.account.jrc_crm_deals).where(contact_id: contact_ids).or(
      visibility.crm(@context.account.jrc_crm_deals).where(company_id: customer.filter_map(&:first))
    )
    orders = visibility.crm(@context.account.jrc_crm_sales_orders).where(contact_id: contact_ids).or(
      visibility.crm(@context.account.jrc_crm_sales_orders).where(deal_id: deals.select(:id))
    )
    contract_scope = visibility.crm(@context.account.jrc_crm_contracts)
    contracts = contract_scope.where(contact_id: contact_ids).or(contract_scope.where(deal_id: deals.select(:id))).or(
      contract_scope.where(sales_order_id: orders.select(:id))
    ).where(status: %w[active expiring])
    actions = @context.records(JrcRelationship::Action).where(assignment_id: ids, status: JrcRelationship::Action::ACTIVE_STATUSES)
    risks = @context.records(JrcRelationship::RiskCase).where(assignment_id: ids)
    closed_risks = period ? risks.where(closed_at: period) : risks
    renewals = @context.records(JrcRelationship::Renewal).where(assignment_id: ids, status: %w[open negotiating])
    expansion = @context.records(JrcRelationship::ExpansionSignal).where(assignment_id: ids)
    visible_conversations = visibility.conversations.where(contact_id: contact_ids)
    csat = shared_csat(ids, visible_conversations)
    csat = csat.where(created_at: period || (90.days.ago..Time.current))
    nps = @context.records(JrcRelationship::Survey).where(assignment_id: ids, kind: 'nps').where(responded_at: period || (90.days.ago..Time.current))
    risk_health = health.where(band: %w[risk critical])
    overdue = visibility.crm(@context.account.jrc_crm_activities, owner: :user_id).where(contact_id: contact_ids).or(
      visibility.crm(@context.account.jrc_crm_activities, owner: :user_id).where(company_id: customer.filter_map(&:first))
    ).overdue
    { customers: scope.count, active: scope.where(status: 'active').count,
      mrr_cents: visibility.crm? ? contracts.sum(:monthly_cents) : nil,
      arr_cents: visibility.crm? ? contracts.sum(:monthly_cents) * 12 : nil,
      health_average: health.average(:score)&.to_f, bands: health.group(:band).count,
      health_coverage: { calculated: health.count, portfolio: scope.count },
      at_risk: health.exists? ? risk_health.count : nil, churned: period ? closed_risks.where(status: 'churn').count : scope.where(status: 'churned').count,
      mrr_at_risk_cents: visibility.crm? && health.exists? ? risk_health.sum("COALESCE((signals ->> 'mrr_cents')::bigint, 0)") : nil,
      retained: closed_risks.where(status: 'retained').count,
      retention_rate: closed_risks.where(status: %w[retained churn]).exists? ? 100.0 * closed_risks.where(status: 'retained').count / closed_risks.where(status: %w[retained churn]).count : nil,
      without_contact: health.exists? ? health.where("(signals ->> 'days_without_contact')::integer >= ?", @context.configuration.effective_rules['no_contact_days']).count : nil,
      overdue_activities: visibility.crm? ? overdue.count : nil,
      nps: nps.exists? ? 100.0 * (nps.where('score >= 9').count - nps.where('score <= 6').count) / nps.count : nil,
      csat: csat.average(:rating)&.to_f,
      renewals: renewal_counts(renewals, visibility),
      actions_today: actions.where(sla_paused_at: nil, due_at: Time.current.all_day).count,
      overdue_actions: actions.where(sla_paused_at: nil).where('due_at < ?', Time.current).count,
      waiting_customer_actions: actions.where(status: 'waiting_customer').count,
      waiting_finance_actions: actions.where(status: 'waiting_finance').count,
      priority_actions: priority_actions(actions),
      expansion_potential_cents: visibility.crm? ? JrcRelationship::ExpansionPipeline.open(expansion, deals).sum(:potential_cents) : nil,
      expansion_won_cents: visibility.crm? ? visibility.crm(@context.account.jrc_crm_deals).where(id: expansion.select(:deal_id), status: 'won').sum(:value_cents) : nil,
      **revenue_metrics(scope, snapshots, period),
      mrr_evolution: JrcRelationship::RevenueEvolution.new(context: @context, scope: scope, period: period).call,
      health_trend: health_history(snapshots, period),
      **JrcRelationship::ReportMetrics.new(context: @context, scope: scope, health: health, period: period, csat: csat).call,
      **JrcRelationship::HealthInsights.new(scope: scope, snapshots: snapshots, latest: health, period: period).call,
      unavailable: %w[product_telemetry_without_source],
      scope: 'authorized_portfolio', period: period && { from: period.begin, to: period.end }, calculated_at: Time.current }
  end

  def shared_csat(ids, conversations)
    JrcRelationship::SurveyMetrics.csat(
      context: @context, surveys: @context.records(JrcRelationship::Survey).where(assignment_id: ids), conversations: conversations
    )
  end

  def renewal_counts(renewals, visibility)
    @context.configuration.effective_rules['renewal_window_days'].index_with do |days|
      visibility.crm? ? renewals.where(renewal_on: Date.current..(Date.current + days)).count : nil
    end
  end

  def priority_actions(actions)
    actions.includes(assignment: [:company, :contact]).order(priority: :desc, due_at: :asc, id: :asc).limit(10).map do |action|
      { assignment_id: action.assignment_id, customer: action.assignment.label, reason: action.reason,
        priority: action.priority, due_at: action.due_at, status: action.status, factors: action.factors }
    end
  end
  private :shared_csat, :renewal_counts, :priority_actions

  def preload(records)
    ids = records.map(&:id)
    signature = @context.access_signature
    scope = JrcRelationship::HealthSnapshot.where(account_id: @context.account.id, viewer_id: @context.user.id, assignment_id: ids,
                                                  access_signature: signature)
    scope = JrcRelationship::SnapshotAccess.scope(@context, scope)
    @snapshots = scope.where(id: scope.select('MAX(id) AS id').group(:assignment_id)).index_by(&:assignment_id)
    @next_actions = @context.records(JrcRelationship::Action).where(assignment_id: ids, status: JrcRelationship::Action::ACTIVE_STATUSES)
                            .select('DISTINCT ON (assignment_id) jrc_relationship_actions.*').order(:assignment_id, priority: :desc, due_at: :asc, id: :asc).index_by(&:assignment_id)
    @risks = @context.records(JrcRelationship::RiskCase).where(assignment_id: ids, status: %w[detected analyzing planned negotiating])
                     .pluck(:assignment_id, :id, :severity, :reason).group_by(&:first).transform_values { |rows|
      rows.map { |_assignment, id, severity, reason|
        { id: id, severity: severity, reason: reason }
      }
    }
    @expansions = JrcRelationship::ExpansionPipeline.open(@context.records(JrcRelationship::ExpansionSignal).where(assignment_id: ids),
                                                          JrcCustomers::Visibility.new(account: @context.account, user: @context.user,
                                                                                       account_user: @context.member).crm(@context.account.jrc_crm_deals))
                                                    .group(:assignment_id).sum(:potential_cents) if JrcOperations::Access.crm?(@context.member)
    @risk_actions = @context.records(JrcRelationship::Action).where(assignment_id: ids)
                            .where("metadata ? 'relationship_risk_id'").includes(:operations_sla_policy).to_a.index_by { |action| action.metadata['relationship_risk_id'].to_s }
    missing = records.filter_map do |record|
      snapshot = @snapshots[record.id]
      record.id if !snapshot || snapshot.calculated_at < 15.minutes.ago || snapshot.config_version != @context.configuration(record).version || snapshot.config_scope_key != @context.configuration(record).scope_key
    end
    unless missing.empty?
      Rails.cache.fetch("relationship-refresh:#{@context.account.id}:#{@context.user.id}:#{signature}:#{missing.join(',')}", expires_in: 1.minute) do
        JrcRelationship::RefreshJob.perform_later(@context.member.id, missing)
        true
      end
    end
    self
  end

  private

  def revenue_metrics(scope, snapshots, period)
    start_at = period&.begin || 30.days.ago
    end_at = period&.end || Time.current
    first = snapshots.where('calculated_at <= ?', start_at)
    first = first.where(id: first.select('MAX(id) AS id').group(:assignment_id))
    last = snapshots.where('calculated_at > ? AND calculated_at <= ?', start_at, end_at)
    last = last.where(id: last.select('MAX(id) AS id').group(:assignment_id))
    opening = first.pluck(:assignment_id, Arel.sql("(signals ->> 'mrr_cents')::bigint")).to_h
    closing = last.pluck(:assignment_id, Arel.sql("(signals ->> 'mrr_cents')::bigint")).to_h
    values = JrcRelationship::RevenueMetrics.call(opening: opening, closing: closing)
    values.merge(revenue_period: { from: start_at, to: end_at }, portfolio_customers: scope.count)
  end

  def health_history(snapshots, period)
    rows = snapshots.where(calculated_at: period || (30.days.ago..Time.current))
    timezone = ActiveRecord::Base.connection.quote(Time.zone.tzinfo.name)
    day = "DATE(calculated_at AT TIME ZONE 'UTC' AT TIME ZONE #{timezone})"
    ids = rows.select("DISTINCT ON (assignment_id, #{day}) id").order(Arel.sql("assignment_id, #{day}, calculated_at DESC, id DESC"))
    rows.where(id: ids).group(Arel.sql(day)).order(Arel.sql(day)).average(:score)
        .map { |date, value| { day: date, score: value&.to_f } }
  end

  def snapshots
    @snapshots ||= {}
  end

  def next_actions
    @next_actions ||= {}
  end

  public

  def recommendations(record)
    signals = JrcRelationship::CustomerSignals.new(assignment: record, context: @context).call
    reasons = signals[:health][:factors].select { |f| f[:available] && f[:normalized] < 60 }
    { customer: record.label, health: signals[:health], evidence: reasons,
      recommended_action: reasons.empty? ? 'Manter cadência de relacionamento' : 'Revisar fatores e preparar plano com o responsável',
      external_actions_require_confirmation: true }
  end
end
