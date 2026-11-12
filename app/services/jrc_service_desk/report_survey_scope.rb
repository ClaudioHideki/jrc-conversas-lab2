# frozen_string_literal: true

class JrcServiceDesk::ReportSurveyScope
  def self.for(query)
    context = query.context
    return JrcRelationship::Survey.none unless context.capability?(:customers_view) &&
                                               JrcRelationship::ModulePolicy.new(context.to_h, context.account).access?

    relationship = JrcRelationship::Context.new(context.account_user)
    rows = relationship.records(JrcRelationship::Survey, survey_action: 'report')
                       .where(source_type: 'JrcServiceDesk::Ticket', source_id: query.relation_for('customers_view').select(:id))
                       .where("metadata ->> 'unit_id' = ?", query.unit.id.to_s)
    JrcRelationship::SurveyModelAccess.visible_scope(relationship, rows, action: 'report', share: 'share_reports')
  end

  def self.summary(query)
    rows = self.for(query)
    return nil unless rows.exists?

    context = JrcRelationship::Context.new(query.context.account_user)
    JrcRelationship::SurveySummary.new(context, rows, cohort: rows, selected_period: true,
                                                      cohort_period: { basis: 'authorized_ticket_opening_cohort' }).call
  end
end
