class JrcRelationship::SurveyDispatchJob < ApplicationJob
  queue_as :default

  def perform(id)
    survey = JrcRelationship::Survey.find_by(id: id)
    return unless survey

    survey.with_lock { dispatch(survey) }
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    record_failure(survey, status: 'blocked', code: 'source_access_denied')
  rescue ArgumentError, KeyError
    record_failure(survey, status: 'failed', code: 'channel_configuration_invalid')
  rescue StandardError
    # The provider boundary never retries an unknown external result.
    record_failure(survey, status: 'unknown', code: 'delivery_result_unknown')
    raise
  end

  private

  def record_failure(survey, status:, code:)
    current = JrcRelationship::Survey.find_by(id: survey&.id)
    return unless current

    current.with_lock do
      next unless dispatchable?(current)

      attributes = { status: status, failure_code: code }
      attributes[:failed_at] = Time.current unless status == 'blocked'
      current.update!(attributes)
    end
  end

  def dispatch(survey)
    return unless dispatchable?(survey)
    return survey.update!(status: 'expired') if survey.expires_at <= Time.current
    return if survey.attempts >= survey.rule_snapshot.dig('settings', 'max_attempts').to_i

    execution = JrcRelationship::SurveyExecutionContext.new(survey)
    reason = execution.blocker
    reason = 'policy_disabled' if reason == 'automation_disabled'
    return survey.update!(status: 'blocked', failure_code: reason) if reason
    return survey.update!(status: 'available') if survey.rule_snapshot.dig('settings', 'channel') == 'public_link'

    dispatch_message(survey, execution)
  end

  def dispatchable?(survey)
    %w[scheduled failed].include?(survey.status) && !survey.responded_at
  end

  def dispatch_message(survey, execution)
    conversation = execution.conversation
    return survey.update!(status: 'blocked', failure_code: 'channel_unavailable') unless conversation

    survey.update!(attempts: survey.attempts + 1)
    JrcRelationship::SurveyDelivery.new(context: execution.context, survey: survey,
                                        base_url: ENV.fetch('FRONTEND_URL')).call(conversation_id: conversation.id, configured_template: true)
  end
end
