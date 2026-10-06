class JrcRelationship::ReportMetrics
  def initialize(context:, scope:, health:, period: nil, csat: nil)
    @context, @scope, @health, @period, @csat = context, scope, health, period || (90.days.ago..Time.current), csat
  end
  def call
    ids = @scope.select(:id)
    qbrs = @context.records(JrcRelationship::Qbr).where(assignment_id: ids, scheduled_at: @period)
    renewals = @context.records(JrcRelationship::Renewal).where(assignment_id: ids, renewal_on: @period.begin.to_date..@period.end.to_date)
    visibility = JrcCustomers::Visibility.new(account: @context.account, user: @context.user, account_user: @context.member)
    renewed = visibility.crm(@context.account.jrc_crm_contracts).where(source_contract_id: renewals.select(:contract_id), signature_status: 'signed')
    won_count = renewed.distinct.count(:source_contract_id)
    surveys = @context.records(JrcRelationship::Survey).where(assignment_id: ids, kind: 'nps', responded_at: @period)
    actions = @context.records(JrcRelationship::Action).where(assignment_id: ids, first_action_at: @period)
    timezone = ActiveRecord::Base.connection.quote(Time.zone.tzinfo.name)
    survey_day = Arel.sql("DATE(responded_at AT TIME ZONE 'UTC' AT TIME ZONE #{timezone})")
    csat_day = Arel.sql("DATE(created_at AT TIME ZONE 'UTC' AT TIME ZONE #{timezone})")
    nps_expression = Arel.sql('100.0 * (SUM(CASE WHEN score >= 9 THEN 1 ELSE 0 END) - SUM(CASE WHEN score <= 6 THEN 1 ELSE 0 END)) / COUNT(*)')
    negative = @health.pluck(:factors).flatten(1).select { |row| row['available'] && row['normalized'].to_f < 60 }
      .group_by { |row| row['factor'] }.map { |factor, rows| { factor: factor, customers: rows.size,
        average: (rows.sum { |row| row['normalized'].to_f } / rows.size).round(1) } }.sort_by { |row| [row[:average], -row[:customers]] }
    { qbr_completed: qbrs.where(status: 'completed').count, qbr_scheduled: qbrs.where(status: 'scheduled').count,
      renewal_rate: visibility.crm? && renewals.exists? ? 100.0 * won_count / renewals.count : nil,
      renewed_mrr_cents: visibility.crm? ? renewed.sum(:monthly_cents) : nil,
      nps_promoters: surveys.where('score >= 9').count, nps_detractors: surveys.where('score <= 6').count,
      nps_evolution: surveys.group(survey_day).order(survey_day).pluck(survey_day, nps_expression, Arel.sql('COUNT(*)'))
        .map { |day, value, count| { day: day, score: value&.to_f, responses: count } },
      csat_evolution: @csat ? @csat.group(csat_day).order(csat_day).average(:rating).map { |day, value| { day: day, score: value&.to_f } } : [],
      first_action_minutes: actions.where("metadata ? 'first_action_elapsed_seconds'")
        .average("(metadata ->> 'first_action_elapsed_seconds')::numeric / 60")&.to_f,
      negative_factors: negative,
      open_retention_cases: @context.records(JrcRelationship::RiskCase).where(assignment_id: ids, status: %w[detected analyzing planned negotiating]).count }
  end
end
