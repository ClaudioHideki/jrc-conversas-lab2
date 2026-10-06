# Read-only lineage of the records used by the dashboard. Both the portfolio
# scope and every native source are authorized before pagination or aggregation.
class JrcRelationship::MetricDrilldown
  def initialize(context:, scope:, period: nil)
    @context, @scope, @period = context, scope, period
    @ids = scope.select(:id)
    @visibility = JrcCustomers::Visibility.new(account: context.account, user: context.user, account_user: context.member)
  end

  def call(metric:, page: 1, day: nil)
    if day.present?
      raise ArgumentError, 'Daily drilldown is only available for health, NPS and CSAT' unless %w[health_average nps csat].include?(metric)
      @day = Date.iso8601(day.to_s).all_day
      @period = @day unless metric == 'health_average'
    end
    values = JrcRelationship::Presenter.new(@context).dashboard(@scope, period: @period)
    raise ArgumentError, 'Unknown dashboard metric' unless values.key?(metric.to_sym)
    relation, aggregation = sources(metric)
    value = @day && metric == 'health_average' ? relation.average(:score)&.to_f : values.fetch(metric.to_sym)
    number = page.to_i.clamp(1, 10_000)
    rows = relation.reorder(:id).limit(25).offset((number - 1) * 25).to_a
    { metric: metric, value: value, aggregation: aggregation, total: relation.count, day: @day&.begin&.to_date,
      calculation: calculation(metric, relation), page: number, per_page: 25, payload: rows.map { |record| present(record, metric) } }
  end

  private

  def records(model)
    @context.records(model).where(assignment_id: @ids)
  end

  def health
    scope = JrcRelationship::HealthSnapshot.where(account_id: @context.account.id, viewer_id: @context.user.id,
      assignment_id: @ids, access_signature: @context.access_signature)
    scope = JrcRelationship::SnapshotAccess.scope(@context, scope)
    scope = scope.where(calculated_at: @day) if @day
    ids = scope.select('DISTINCT ON (assignment_id) id').order(:assignment_id, calculated_at: :desc, id: :desc)
    @day ? scope.where(id: ids) : scope.where(id: scope.select('MAX(id) AS id').group(:assignment_id))
  end

  def native_sources
    customers = @scope.pluck(:company_id, :contact_id)
    companies = customers.filter_map(&:first)
    contacts = @context.account.contacts.where(company_id: companies).pluck(:id) + customers.filter_map(&:last)
    deals = @visibility.crm(@context.account.jrc_crm_deals).where(contact_id: contacts).or(
      @visibility.crm(@context.account.jrc_crm_deals).where(company_id: companies))
    orders = @visibility.crm(@context.account.jrc_crm_sales_orders).where(contact_id: contacts).or(
      @visibility.crm(@context.account.jrc_crm_sales_orders).where(deal_id: deals.select(:id)))
    contracts = @visibility.crm(@context.account.jrc_crm_contracts)
    activities = @visibility.crm(@context.account.jrc_crm_activities, owner: :user_id)
    { contracts: contracts.where(contact_id: contacts).or(contracts.where(deal_id: deals.select(:id)))
        .or(contracts.where(sales_order_id: orders.select(:id))).where(status: %w[active expiring]),
      activities: activities.where(contact_id: contacts).or(activities.where(company_id: companies)).overdue,
      csat: CsatSurveyResponse.where(account_id: @context.account.id,
        conversation_id: @visibility.conversations.where(contact_id: contacts).select(:id),
        created_at: @period || (90.days.ago..Time.current)) }
  end

  def sources(metric)
    risks = records(JrcRelationship::RiskCase)
    risks = risks.where(closed_at: @period) if @period
    actions = records(JrcRelationship::Action).where(status: JrcRelationship::Action::ACTIVE_STATUSES)
    surveys = records(JrcRelationship::Survey).where(kind: 'nps', responded_at: @period || (90.days.ago..Time.current))
    expansion = records(JrcRelationship::ExpansionSignal)
    case metric
    when 'customers' then [@scope, 'count']
    when 'active' then [@scope.where(status: 'active'), 'count']
    when 'churned' then [@period ? risks.where(status: 'churn') : @scope.where(status: 'churned'), 'count']
    when 'mrr_cents', 'arr_cents' then [native_sources[:contracts], 'sum']
    when 'health_average' then [health.where.not(score: nil), 'average']
    when 'at_risk', 'mrr_at_risk_cents' then [health.where(band: %w[risk critical]), metric == 'at_risk' ? 'count' : 'sum']
    when 'without_contact'
      [health.where("(signals ->> 'days_without_contact')::integer >= ?", @context.configuration.effective_rules['no_contact_days']), 'count']
    when 'retained' then [risks.where(status: 'retained'), 'count']
    when 'retention_rate' then [risks.where(status: %w[retained churn]), 'ratio']
    when 'open_retention_cases' then [records(JrcRelationship::RiskCase).where(status: %w[detected analyzing planned negotiating]), 'count']
    when 'actions_today' then [actions.where(sla_paused_at: nil, due_at: Time.current.all_day), 'count']
    when 'overdue_actions' then [actions.where(sla_paused_at: nil).where('due_at < ?', Time.current), 'count']
    when 'waiting_customer_actions' then [actions.where(status: 'waiting_customer'), 'count']
    when 'waiting_finance_actions' then [actions.where(status: 'waiting_finance'), 'count']
    when 'overdue_activities' then [native_sources[:activities], 'count']
    when 'nps' then [surveys, 'ratio']
    when 'nps_promoters' then [surveys.where('score >= 9'), 'count']
    when 'nps_detractors' then [surveys.where('score <= 6'), 'count']
    when 'csat' then [native_sources[:csat], 'average']
    when 'ces' then [records(JrcRelationship::Survey).where(kind: 'ces', responded_at: @period || (90.days.ago..Time.current)), 'average']
    when 'expansion_potential_cents' then [JrcRelationship::ExpansionPipeline.open(expansion, @visibility.crm(@context.account.jrc_crm_deals)), 'sum']
    when 'expansion_won_cents'
      [@visibility.crm(@context.account.jrc_crm_deals).where(id: expansion.select(:deal_id), status: 'won'), 'sum']
    when 'qbr_completed', 'qbr_scheduled'
      [records(JrcRelationship::Qbr).where(status: metric == 'qbr_completed' ? 'completed' : 'scheduled',
        scheduled_at: @period || (90.days.ago..Time.current)), 'count']
    when 'first_action_minutes'
      [records(JrcRelationship::Action).where(first_action_at: @period || (90.days.ago..Time.current))
        .where("metadata ? 'first_action_elapsed_seconds'"), 'average']
    when 'renewal_rate', 'renewed_mrr_cents'
      period = @period || (90.days.ago..Time.current)
      renewals = records(JrcRelationship::Renewal).where(renewal_on: period.begin.to_date..period.end.to_date)
      return [renewals, 'ratio'] if metric == 'renewal_rate'
      [@visibility.crm(@context.account.jrc_crm_contracts).where(source_contract_id: renewals.select(:contract_id), signature_status: 'signed'),
        metric == 'renewal_rate' ? 'ratio' : 'sum']
    when 'nrr', 'gross_retention', 'revenue_churn'
      # Expose the actual opening/closing cohort, not newly acquired customers.
      snapshots = JrcRelationship::HealthSnapshot.where(account_id: @context.account.id, viewer_id: @context.user.id,
        assignment_id: @ids, access_signature: @context.access_signature)
      snapshots = JrcRelationship::SnapshotAccess.scope(@context, snapshots)
      opening = snapshots.where('calculated_at <= ?', @period&.begin || 30.days.ago)
      opening = opening.where(id: opening.select('MAX(id) AS id').group(:assignment_id))
      [opening.where("(signals ->> 'mrr_cents')::bigint > 0"), 'cohort']
    else
      raise ArgumentError, 'Metric has no record drilldown'
    end
  end

  def calculation(metric, relation)
    case metric
    when 'nps'
      { promoters: relation.where('score >= 9').count, detractors: relation.where('score <= 6').count, denominator: relation.count }
    when 'retention_rate'
      { numerator: relation.where(status: 'retained').count, denominator: relation.count }
    when 'renewal_rate'
      renewed = @visibility.crm(@context.account.jrc_crm_contracts).where(source_contract_id: relation.select(:contract_id), signature_status: 'signed')
      { numerator: renewed.distinct.count(:source_contract_id), denominator: relation.count }
    end
  end

  def present(record, metric)
    row = { id: record.id, source_type: record.class.name, source_kind: record.class.name.demodulize.underscore, status: record.try(:status),
            label: record.try(:title) || record.try(:reason) || record.try(:contract_number) || record.try(:label) || record.id.to_s,
            date: record.try(:due_at) || record.try(:scheduled_at) || record.try(:ends_on) || record.try(:calculated_at) || record.created_at }
    assignment = record.is_a?(JrcRelationship::Assignment) ? record : record.try(:assignment)
    if assignment
      row.merge!(assignment_id: assignment.id, customer: assignment.label)
      row[:route] = { name: 'jrc_relationship_health', params: { accountId: @context.account.id }, query: { assignment_id: assignment.id, customer: assignment.id } }
    end
    case record
    when JrcRelationship::HealthSnapshot
      row.merge!(score: record.score, amount_cents: record.signals['mrr_cents'], band: record.band)
      if %w[nrr gross_retention revenue_churn].include?(metric)
        closing = JrcRelationship::HealthSnapshot.where(account_id: @context.account.id, viewer_id: @context.user.id,
          assignment_id: record.assignment_id, access_signature: @context.access_signature)
          .where('calculated_at > ? AND calculated_at <= ?', @period&.begin || 30.days.ago, @period&.end || Time.current)
        closing = JrcRelationship::SnapshotAccess.scope(@context, closing).order(:id).last
        row[:closing_cents] = closing&.signals&.dig('mrr_cents')
      end
    when JrcCrm::Contract
      row[:amount_cents] = record.monthly_cents * (metric == 'arr_cents' ? 12 : 1)
      row[:route] = { name: 'crm_contracts', params: { accountId: @context.account.id }, query: { contractId: record.id } }
    when JrcCrm::Activity
      row[:route] = { name: 'crm_activities', params: { accountId: @context.account.id }, query: { activityId: record.id } }
    when JrcCrm::Deal
      row[:amount_cents] = record.value_cents
      row[:route] = { name: 'crm_deals', params: { accountId: @context.account.id }, query: { dealId: record.id } }
    when JrcRelationship::ExpansionSignal then row[:amount_cents] = record.potential_cents
    when JrcRelationship::Survey
      row.merge!(score: record.score, comment: record.comment, date: record.responded_at)
    when JrcRelationship::Renewal
      contract = record.assignment.customer_context(@context.member).contracts.find(record.contract_id)
      row.merge!(label: contract.contract_number, date: record.renewal_on, amount_cents: contract.monthly_cents,
        route: { name: 'crm_contracts', params: { accountId: @context.account.id }, query: { contractId: contract.id } })
    when CsatSurveyResponse
      row.merge!(score: record.rating, comment: record.feedback_message)
      row[:route] = { name: 'inbox_conversation', params: { accountId: @context.account.id, conversation_id: record.conversation.display_id } }
    when JrcRelationship::Action
      row[:elapsed_minutes] = record.metadata['first_action_elapsed_seconds']&.to_f&./(60)
    end
    row
  end
end
