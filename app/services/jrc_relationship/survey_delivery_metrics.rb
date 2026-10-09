# Only audited shared-engine enrollment and persisted provider timestamps are
# delivery evidence. Public links and legacy rows are disclosed separately.
class JrcRelationship::SurveyDeliveryMetrics
  def initialize(context, scope, available: true, period: {})
    @context = context
    @scope = scope
    @available = available
    @period = period
  end

  def call
    return { available: false, reason: 'response_period_requires_cohort', period: @period } unless @available

    eligible = @scope.where(id: decisions.select(:survey_id))
    { available: true, source: 'authorized_survey_enrollment_and_native_delivery', period: @period }
      .merge(enrollment(eligible), delivery(eligible), tracking)
  end

  private

  def decisions
    JrcRelationship::SurveyDispatchDecision.where(account: @context.account, state: 'scheduled', reason: 'eligible',
                                                  survey_id: @scope.select(:id))
  end

  def enrollment(eligible)
    total = eligible.count
    answered = eligible.where.not(responded_at: nil).count
    { eligible_count: total, eligible_answered_count: answered,
      available_link_count: eligible.where(status: 'available').count, queued_count: eligible.where(status: %w[queued dispatching]).count,
      failed_count: eligible.where(status: %w[failed blocked unknown]).count,
      response_rate: total.positive? ? 100.0 * answered / total : nil,
      response_numerator: answered, response_denominator: total }
  end

  def delivery(eligible)
    sent = eligible.where.not(sent_at: nil).count
    delivered = eligible.where.not(delivered_at: nil)
    confirmed = delivered.where.not(sent_at: nil).count
    { sent_count: sent, delivered_count: delivered.count,
      delivery_rate: sent.positive? ? 100.0 * confirmed / sent : nil,
      delivery_numerator: confirmed, delivery_denominator: sent }
  end

  def tracking
    { legacy_count: @scope.where(source_type: nil).count,
      untracked_count: @scope.where.not(id: decisions.select(:survey_id)).where.not(source_type: nil).count }
  end
end
