class JrcRelationship::ReportMetrics
  def initialize(context:, scope:, health:, period: nil, csat: nil)
    @context, @scope, @health, @period, @csat = context, scope, health, period || (90.days.ago..Time.current), csat
  end

  def call
    qbr_metrics.merge(renewal_metrics).merge(satisfaction_metrics).merge(action_metrics).merge(health_metrics)
  end

  private

  def records(model)
    @context.records(model).where(assignment_id: @scope.select(:id))
  end

  def qbr_metrics
    qbrs = records(JrcRelationship::Qbr).where(scheduled_at: @period)
    { qbr_completed: qbrs.where(status: 'completed').count, qbr_scheduled: qbrs.where(status: 'scheduled').count }
  end

  def renewal_metrics
    renewals = records(JrcRelationship::Renewal).where(renewal_on: @period.begin.to_date..@period.end.to_date)
    visibility = JrcCustomers::Visibility.new(account: @context.account, user: @context.user, account_user: @context.member)
    renewal_cohort = JrcRelationship::RenewalOutcome.cohort(@context, renewals)
    { renewal_rate: renewal_rate(renewal_cohort, visibility),
      renewal_coverage: renewal_cohort.except(:contracts).merge(period: { from: @period.begin, to: @period.end }),
      renewed_mrr_cents: visibility.crm? ? renewal_cohort[:contracts].sum(:monthly_cents) : nil }
  end

  def renewal_rate(cohort, visibility)
    return unless visibility.crm? && cohort[:source_count].positive?

    100.0 * cohort[:renewed_count] / cohort[:source_count]
  end

  def satisfaction_metrics
    surveys = records(JrcRelationship::Survey).where(kind: 'nps', responded_at: @period)
    ces = records(JrcRelationship::Survey).where(kind: 'ces', responded_at: @period)
    { ces: ces.average(:score)&.to_f,
      nps_promoters: surveys.where('score >= 9').count, nps_detractors: surveys.where('score <= 6').count,
      nps_evolution: nps_evolution(surveys), csat_evolution: csat_evolution }
  end

  def local_day(column)
    timezone = ActiveRecord::Base.connection.quote(Time.zone.tzinfo.name)
    Arel.sql("DATE(#{column} AT TIME ZONE 'UTC' AT TIME ZONE #{timezone})")
  end

  def nps_evolution(surveys)
    survey_day = local_day('responded_at')
    nps_expression = Arel.sql('100.0 * (SUM(CASE WHEN score >= 9 THEN 1 ELSE 0 END) - SUM(CASE WHEN score <= 6 THEN 1 ELSE 0 END)) / COUNT(*)')
    surveys.group(survey_day).order(survey_day).pluck(survey_day, nps_expression, Arel.sql('COUNT(*)'))
           .map { |day, value, count| { day: day, score: value&.to_f, responses: count } }
  end

  def csat_evolution
    return [] unless @csat

    day = local_day('created_at')
    @csat.group(day).order(day).average(:rating).map { |date, value| { day: date, score: value&.to_f } }
  end

  def action_metrics
    actions = records(JrcRelationship::Action).where(first_action_at: @period)
    { first_action_minutes: actions.where("metadata ? 'first_action_elapsed_seconds'")
                                   .average("(metadata ->> 'first_action_elapsed_seconds')::numeric / 60")&.to_f }
  end

  def health_metrics
    { negative_factors: negative_factors,
      open_retention_cases: records(JrcRelationship::RiskCase).where(status: %w[detected analyzing planned negotiating]).count }
  end

  def negative_factors
    factors = @health.pluck(:factors).flatten(1).select { |row| row['available'] && row['normalized'].to_f < 60 }
    factors.group_by { |row| row['factor'] }.map { |factor, rows| negative_factor(factor, rows) }
           .sort_by { |row| [row[:average], -row[:customers]] }
  end

  def negative_factor(factor, rows)
    { factor: factor, customers: rows.size, average: (rows.sum { |row| row['normalized'].to_f } / rows.size).round(1) }
  end
end
