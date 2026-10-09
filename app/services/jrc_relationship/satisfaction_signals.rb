class JrcRelationship::SatisfactionSignals
  def initialize(context, assignment, customer, rules)
    @context = context
    @assignment = assignment
    @customer = customer
    @rules = rules
  end

  def call
    surveys = @context.records(JrcRelationship::Survey).where(assignment: @assignment)
    nps = surveys.where(kind: 'nps').where.not(responded_at: nil).where('responded_at >= ?', 90.days.ago)
    ces = surveys.where(kind: 'ces', responded_at: 90.days.ago..Time.current)
    csat = native_csat
    { surveys: surveys, nps: nps, ces: ces, csat: csat, nps_score: nps.average(:score)&.to_f, ces_score: ces.average(:score)&.to_f,
      ces_normalized: ces.average("CASE WHEN definition_snapshot -> 'settings' ->> 'ces_direction' = 'lower_is_better' " \
                                 'THEN 100 - score * 10 ELSE score * 10 END')&.to_f,
      csat_score: csat_score(surveys), unmanaged: unmanaged?(nps, ces, csat) }
  end

  private

  def native_csat
    CsatSurveyResponse.where(account_id: @context.account.id, conversation_id: @customer.conversations.select(:id))
                      .where('created_at >= ?', 90.days.ago)
  end

  def csat_score(surveys)
    JrcRelationship::SurveyMetrics.csat(context: @context, surveys: surveys, conversations: @customer.conversations)
                                  .where('created_at >= ?', 90.days.ago).average(:rating)&.to_f
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
