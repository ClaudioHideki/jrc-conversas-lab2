# Grouped SQL keeps query count independent from the number of agents.
class JrcRelationship::TeamMetrics
  def initialize(context:, scope:, period: nil)
    @context, @scope, @period = context, scope, period
  end

  def call
    result = @scope.where.not(owner_id: nil).group(:owner_id).count.transform_values do |count|
      { customers: count, mrr_cents: nil, health_average: nil, at_risk: nil, overdue_actions: 0, waiting_customer_actions: 0,
        churned: 0, retained: 0, retention_rate: nil, overdue_activities: nil, without_contact: nil, expansion_potential_cents: nil, expansion_won_cents: nil,
        nps: nil, csat: nil, renewals_60: JrcOperations::Access.crm?(@context.member) ? 0 : nil, renewals: {} }
    end
    ids = @scope.select(:id)
    health = JrcRelationship::HealthSnapshot.where(account_id: @context.account.id, viewer_id: @context.user.id,
      assignment_id: ids, access_signature: @context.access_signature)
    health = JrcRelationship::SnapshotAccess.scope(@context, health)
    health = health.where(id: health.select('MAX(id) AS id').group(:assignment_id))
    grouped(health).count.each_key do |owner|
      next unless result[owner]
      result[owner].merge!(at_risk: 0, without_contact: 0)
    end
    merge!(result, :health_average, grouped(health).average(:score), numeric: true)
    merge!(result, :at_risk, grouped(health.where(band: %w[risk critical])).count)
    merge!(result, :without_contact, grouped(health.where("(signals ->> 'days_without_contact')::integer >= ?", @context.configuration.effective_rules['no_contact_days'])).count)
    merge!(result, :mrr_cents, grouped(health).sum("(signals ->> 'mrr_cents')::bigint")) if JrcOperations::Access.crm?(@context.member)
    actions = @context.records(JrcRelationship::Action).where(assignment_id: ids, status: JrcRelationship::Action::ACTIVE_STATUSES)
    merge!(result, :overdue_actions, grouped(actions.where(sla_paused_at: nil).where('due_at < ?', Time.current)).count)
    merge!(result, :waiting_customer_actions, grouped(actions.where(status: 'waiting_customer')).count)
    risks = @context.records(JrcRelationship::RiskCase).where(assignment_id: ids)
    risks = risks.where(closed_at: @period) if @period
    merge!(result, :retained, grouped(risks.where(status: 'retained')).count)
    churn = @period ? grouped(risks.where(status: 'churn')).count : @scope.where(status: 'churned').group(:owner_id).count
    merge!(result, :churned, churn)
    expansion = @context.records(JrcRelationship::ExpansionSignal).where(assignment_id: ids)
    merge!(result, :expansion_potential_cents, grouped(expansion.where(status: %w[suggested approved converted])).sum(:potential_cents))
    if JrcOperations::Access.crm?(@context.member)
      visibility = JrcCustomers::Visibility.new(account: @context.account, user: @context.user, account_user: @context.member)
      won = visibility.crm(@context.account.jrc_crm_deals).where(status: 'won').select(:id)
      result.each_value { |metrics| metrics[:expansion_won_cents] = 0 }
      result.each_value { |metrics| metrics[:expansion_potential_cents] ||= 0 }
      merge!(result, :expansion_won_cents, grouped(expansion.where(deal_id: won).joins(:deal)).sum('jrc_crm_deals.value_cents'))
    end
    renewals = @context.records(JrcRelationship::Renewal).where(assignment_id: ids, status: %w[open negotiating])
    [15, 30, 60, 90, 120].each do |days|
      grouped(renewals.where(renewal_on: Date.current..(Date.current + days))).count.each { |owner, count| result[owner][:renewals][days] = count if result[owner] }
    end
    result.each_value { |metrics| metrics[:renewals_60] = metrics[:renewals].fetch(60, 0) if JrcOperations::Access.crm?(@context.member) }
    surveys = @context.records(JrcRelationship::Survey).where(assignment_id: ids, kind: 'nps', responded_at: @period || (90.days.ago..Time.current))
    all, promoters, detractors = grouped(surveys).count, grouped(surveys.where('score >= 9')).count, grouped(surveys.where('score <= 6')).count
    all.each { |owner, count| result[owner][:nps] = 100.0 * (promoters.fetch(owner, 0) - detractors.fetch(owner, 0)) / count if result[owner] }
    csat!(result)
    result.each_value do |metrics|
      total = metrics[:retained] + metrics[:churned]
      metrics[:retention_rate] = total.positive? ? 100.0 * metrics[:retained] / total : nil
    end
    overdue_activities!(result)
    completed = @context.records(JrcRelationship::Action).where(assignment_id: ids, first_action_at: @period || (90.days.ago..Time.current))
      .where("metadata ? 'first_action_elapsed_seconds'")
    merge!(result, :first_action_minutes, grouped(completed).average("(metadata ->> 'first_action_elapsed_seconds')::numeric / 60"), numeric: true)
    result
  end

  private

  def grouped(relation)
    relation.joins(:assignment).group('jrc_relationship_assignments.owner_id')
  end

  def merge!(result, key, values, numeric: false)
    values.each { |owner, value| result[owner][key] = numeric ? value&.to_f : value if result[owner] }
  end

  def csat!(result)
    visibility = JrcCustomers::Visibility.new(account: @context.account, user: @context.user, account_user: @context.member)
    join = "INNER JOIN jrc_relationship_assignments ON jrc_relationship_assignments.account_id = csat_survey_responses.account_id AND (jrc_relationship_assignments.contact_id = contacts.id OR jrc_relationship_assignments.company_id = contacts.company_id)"
    values = CsatSurveyResponse.where(account_id: @context.account.id, conversation_id: visibility.conversations.select(:id),
      created_at: @period || (90.days.ago..Time.current)).joins(:contact).joins(join).where(jrc_relationship_assignments: { id: @scope.select(:id) })
      .group('jrc_relationship_assignments.owner_id').average(:rating)
    merge!(result, :csat, values, numeric: true)
  end

  def overdue_activities!(result)
    return unless JrcOperations::Access.crm?(@context.member)
    visibility = JrcCustomers::Visibility.new(account: @context.account, user: @context.user, account_user: @context.member)
    activities = visibility.crm(@context.account.jrc_crm_activities, owner: :user_id).overdue
    join = "INNER JOIN jrc_relationship_assignments ON jrc_relationship_assignments.account_id = jrc_crm_activities.account_id AND " \
      "(jrc_relationship_assignments.company_id = jrc_crm_activities.company_id OR jrc_relationship_assignments.company_id = contacts.company_id " \
      "OR jrc_relationship_assignments.contact_id = jrc_crm_activities.contact_id)"
    values = activities.left_joins(:contact).joins(join).where(jrc_relationship_assignments: { id: @scope.select(:id) })
      .group('jrc_relationship_assignments.owner_id').distinct.count(:id)
    result.each_value { |metrics| metrics[:overdue_activities] = 0 }
    merge!(result, :overdue_activities, values)
  end
end
