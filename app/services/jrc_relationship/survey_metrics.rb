# Shared CSAT responses replace their native adapter row in aggregates instead of adding a second response.
class JrcRelationship::SurveyMetrics
  def self.csat(context:, surveys:, conversations:)
    shared = surveys.where(kind: 'csat').where.not(responded_at: nil).where.not(score: nil)
    # Exclude adapters for ALL managed responses in this Account, not only visible
    # surveys. Otherwise a denied model could reappear through its native CSAT row.
    message_ids = managed_message_ids(context)
    native = CsatSurveyResponse.where(account_id: context.account.id, conversation_id: conversations.select(:id)).where.not(message_id: message_ids)
    columns = 'id, account_id, conversation_id, message_id, rating, created_at, feedback_message, ' \
              "'native_csat'::text AS metric_source, NULL::bigint AS assignment_id"
    native_sql = native.reorder(nil).select(Arel.sql(columns)).to_sql
    columns = "id, account_id, NULL::bigint AS conversation_id, NULL::bigint AS message_id, (#{JrcRelationship::SurveyScale.sql('csat')}) AS rating, " \
              "responded_at AS created_at, comment AS feedback_message, 'shared_survey'::text AS metric_source, assignment_id"
    shared_sql = shared.reorder(nil).select(Arel.sql(columns)).to_sql
    CsatSurveyResponse.from("(#{native_sql} UNION ALL #{shared_sql}) AS csat_survey_responses")
  end

  def self.managed_message_ids(context)
    JrcRelationship::Survey.where(account_id: context.account.id, kind: 'csat')
      .where("metadata ->> 'sent_message_id' ~ '^[0-9]{1,18}$'")
      .select(Arel.sql("(metadata ->> 'sent_message_id')::bigint"))
  end

end
