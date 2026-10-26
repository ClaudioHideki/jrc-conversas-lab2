# Replays durable native events after an enqueue failure. It does not enable
# automation, replay events from before publication, or retry uncertain sends.
class JrcRelationship::SurveyEventRecovery
  def initialize(account)
    @account = account
  end

  def call
    return unless JrcRelationship::SurveyEngine.enabled?(@account)

    rules = JrcRelationship::SurveyRule.where(account: @account, active: true)
                                     .joins(:definition).where(jrc_relationship_survey_definitions: { status: 'active' })
                                     .where("jsonb_exists(jrc_relationship_survey_rules.settings, 'service_desk_model')")
    rules.group_by { |rule| rule.settings.dig('service_desk_model', 'rules', 'event') }.each do |trigger, policies|
      next unless %w[closed first_agent_response].include?(trigger)

      recover_events(trigger, policies)
    end
    recover_dispatch
  end

  private

  def recover_events(trigger, policies)
    units = policies.map { |rule| rule.matchers['unit_id'] }.compact
    events = JrcServiceDesk::TicketEvent.where(account: @account, unit_id: units)
    events = if trigger == 'closed'
               events.where(event_type: 'lifecycle_transitioned').where("data->>'action' = 'close'")
             else
               events.where(event_type: 'first_response_observed')
             end
    events = events.where('jrc_service_desk_ticket_events.created_at >= ?', policies.map(&:updated_at).min)
    events = events.where(<<~SQL.squish, policies.map(&:id))
      NOT EXISTS (SELECT 1 FROM jrc_relationship_survey_dispatch_decisions decisions
        WHERE decisions.account_id = jrc_service_desk_ticket_events.account_id
          AND decisions.source_type = 'JrcServiceDesk::Ticket'
          AND decisions.source_id = jrc_service_desk_ticket_events.ticket_id
          AND decisions.rule_id IN (?)
          AND decisions.evaluated_at >= jrc_service_desk_ticket_events.created_at)
    SQL
    events.find_each(batch_size: 100) do |event|
      recover_event(event, trigger, policies)
    end
  end

  def recover_event(event, trigger, policies)
    ticket = JrcServiceDesk::Ticket.find_by(account: @account, id: event.ticket_id)
    return unless ticket

    reopening = ticket.lifecycle_transitions.where(action: 'reopen').order(:id).last
    return if reopening && reopening.occurred_at > event.created_at

    event_name = trigger == 'closed' ? 'closure' : 'first_agent_response'
    policy = policies.select do |rule|
      rule.updated_at <= event.created_at && JrcRelationship::SurveyModelRuntime.matches?(rule, ticket, event_name)
    end.max_by { |rule| [rule.specificity, rule.priority, rule.version, rule.id] }
    return unless policy

    JrcRelationship::SurveyEngine.evaluate_event(source: ticket, event: event_name,
      rule_id: policy.id, cycle_key: "service-desk:ticket:#{ticket.id}:cycle:#{reopening&.id || 'initial'}")
  rescue StandardError => error
    Rails.logger.error("survey_event_recovery_failed event=#{event.id} class=#{error.class.name}")
  end

  def recover_dispatch
    JrcRelationship::Survey.where(account: @account, status: 'scheduled', attempts: 0)
                          .where('scheduled_at <= ?', Time.current)
                          .where("jsonb_exists(rule_snapshot->'settings', 'service_desk_model')")
                          .find_each(batch_size: 100) do |survey|
      JrcRelationship::SurveyDispatchJob.perform_later(survey.id)
    rescue StandardError => error
      Rails.logger.error("survey_dispatch_recovery_failed survey=#{survey.id} class=#{error.class.name}")
    end
  end
end
