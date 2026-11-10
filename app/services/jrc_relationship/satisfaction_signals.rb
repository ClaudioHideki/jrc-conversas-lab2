class JrcRelationship::SatisfactionSignals
  def initialize(context, assignment, customer, rules)
    @context = context
    @assignment = assignment
    @customer = customer
    @rules = rules
  end

  def call
    surveys = authorized_surveys
    sources = source_relations(surveys)
    samples = sources.transform_values { |relation, column| relation.where(column => window) }
    scores = scores(samples)
    evidence = JrcRelationship::SatisfactionEvidence.new(sources: sources, scores: scores, window_days: window_days, now: window.end).call
    present(surveys, samples, scores, evidence)
  end

  private

  def authorized_surveys
    rows = @context.records(JrcRelationship::Survey, survey_action: 'report').where(assignment: @assignment)
    JrcRelationship::SurveyModelAccess.visible_scope(@context, rows, action: 'report', share: 'share_relationship')
  end

  def source_relations(surveys)
    metrics = JrcRelationship::SurveyMetrics.csat(context: @context, surveys: surveys, conversations: @customer.conversations)
    { nps: [surveys.where(kind: 'nps').where.not(responded_at: nil).where.not(score: nil), :responded_at],
      ces: [surveys.where(kind: 'ces').where.not(responded_at: nil).where.not(score: nil), :responded_at],
      csat: [metrics.where.not(rating: nil), :created_at] }
  end

  def scores(samples)
    { nps: samples[:nps].average(:score)&.to_f, csat: samples[:csat].average(:rating)&.to_f,
      ces: samples[:ces].average(Arel.sql(JrcRelationship::SurveyScale.sql('ces')))&.to_f,
      ces_normalized: samples[:ces].average(Arel.sql("(#{JrcRelationship::SurveyScale.sql('ces', reverse: true)}) * 10"))&.to_f }
  end

  def present(surveys, samples, scores, evidence)
    nps, ces, metrics = samples.values_at(:nps, :ces, :csat)
    csat = native_csat
    { surveys: surveys, nps: nps, ces: ces, csat: csat, nps_score: scores[:nps], ces_score: scores[:ces],
      ces_normalized: scores[:ces_normalized],
      csat_score: scores[:csat], unmanaged: unmanaged?(nps, ces, csat), evidence: evidence[:evidence],
      source_ids: merge_sources(evidence[:source_ids], nps, ces, metrics), window_days: window_days }
  end

  def native_csat
    CsatSurveyResponse.where(account_id: @context.account.id, conversation_id: @customer.conversations.select(:id))
                      .where(created_at: window)
  end

  def window_days
    @rules.fetch('satisfaction_window_days', 90)
  end

  def window
    @window ||= window_days.days.ago..Time.current
  end

  def merge_sources(evidence, nps, ces, metrics)
    native, shared = metrics.pluck(:id, :metric_source).partition { |row| row.last == 'native_csat' }
    { 'surveys' => (nps.pluck(:id) + ces.pluck(:id) + shared.map(&:first) + evidence.fetch('surveys', [])).uniq,
      'csat' => (native.map(&:first) + evidence.fetch('csat', [])).uniq }
  end

  def unmanaged?(nps, ces, csat)
    managed_messages = JrcRelationship::Survey.where(account_id: @context.account.id).where.not(rule_id: nil)
                                              .where("metadata ? 'sent_message_id'").pluck(Arel.sql("(metadata ->> 'sent_message_id')::bigint"))
    nps.where(rule_id: nil).exists?(['score <= 6']) || unmanaged_ces?(ces) ||
      csat.where.not(message_id: managed_messages).exists?(['rating < ?', @rules['csat_threshold']])
  end

  def unmanaged_ces?(ces)
    ces.where(rule_id: nil).exists?(["CASE WHEN definition_snapshot -> 'settings' ->> 'ces_direction' = 'lower_is_better' " \
                                     'THEN score >= ? ELSE score < ? END', @rules['ces_threshold'], @rules['ces_threshold']])
  end
end
