class JrcRelationship::SurveySummary
  def initialize(context, scope, selected_period: false, cohort: nil, **cohort_options)
    raise ArgumentError, 'Unknown survey cohort option' unless (cohort_options.keys - %i[cohort_available cohort_period]).empty?

    @context = context
    @scope = scope
    @selected_period = selected_period
    @cohort = cohort || scope
    @cohort_available = cohort_options.fetch(:cohort_available, true)
    @cohort_period = cohort_options.fetch(:cohort_period, {})
  end

  def call
    answered = @scope.where.not(responded_at: nil)
    scores(answered).merge(analysis(answered), definitions, delivery: delivery)
  end

  private

  def scores(answered)
    { response_count: answered.count, nps: nps_score(answered), calculations: calculations(answered),
      csat: answered.where(kind: 'csat').average(:score)&.to_f,
      ces: answered.where(kind: 'ces').average(:score)&.to_f }
  end

  def calculations(answered)
    nps = answered.where(kind: 'nps')
    { nps: { promoters: nps.where('score >= 9').count, detractors: nps.where('score <= 6').count, denominator: nps.count },
      csat: { denominator: answered.where(kind: 'csat').where.not(score: nil).count },
      ces: { denominator: answered.where(kind: 'ces').where.not(score: nil).count } }
  end

  def analysis(answered)
    { treatment: answered.group(:treatment_status).count, classifications: classification_counts(answered), trend: trend(answered) }
  end

  def definitions
    { models: JrcRelationship::SurveyDefinition.where(account: @context.account, id: @scope.select(:definition_id)).order(:name).pluck(:id, :name),
      rules: JrcRelationship::SurveyRule.where(account: @context.account, id: @scope.select(:rule_id)).order(:name).pluck(:id, :name) }
  end

  def delivery
    JrcRelationship::SurveyDeliveryMetrics.new(@context, @cohort, available: @cohort_available, period: @cohort_period).call
  end

  def nps_score(answered)
    rows = answered.where(kind: 'nps')
    count = rows.count
    100.0 * (rows.where('score >= 9').count - rows.where('score <= 6').count) / count if count.positive?
  end

  def classification_counts(answered)
    answered.group(:kind, :classification).count.map do |(kind, classification), total|
      { kind: kind, classification: classification, count: total }
    end
  end

  def trend(answered)
    timezone = ActiveRecord::Base.connection.quote(Time.zone.tzinfo.name)
    day = "DATE(responded_at AT TIME ZONE 'UTC' AT TIME ZONE #{timezone})"
    answered = answered.where('responded_at >= ?', 90.days.ago) unless @selected_period
    answered.group(Arel.sql(day), :kind).order(Arel.sql(day), :kind)
            .pluck(Arel.sql(day), :kind, Arel.sql('COUNT(*)'), Arel.sql('AVG(score)'),
                   Arel.sql('100.0 * SUM(CASE WHEN score >= 9 THEN 1 WHEN score <= 6 THEN -1 ELSE 0 END) / COUNT(*)'))
            .map do |date, kind, count, average, nps|
      { day: date, kind: kind, response_count: count, average_score: average&.to_f, nps: kind == 'nps' ? nps.to_f : nil }
    end
  end
end
