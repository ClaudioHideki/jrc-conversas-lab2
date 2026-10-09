# frozen_string_literal: true

class JrcNico::Helpdesk::EvidenceAccess
  def initialize(context, ticket, evidence)
    @context = context
    @ticket = ticket
    @evidence = evidence
  end

  def call
    authorize_clock!
    authorize_survey!
    authorize_recovery!
    true
  end

  private

  def authorize_clock!
    id = @evidence['clock_id']
    return unless id

    JrcServiceDesk::SlaClock.where(account_id: @context.account.id, ticket_id: @ticket.id).find(id)
    Pundit.authorize(@context.native.to_h, @ticket, :view_sla?)
  end

  def authorize_survey!
    return unless @evidence['survey_decision_id'] || @evidence['survey_id']

    JrcRelationship::Context.new(@context.member)
    decision = authorized_decision
    survey_id = @evidence['survey_id'] || decision&.survey_id
    return unless survey_id

    @survey = JrcNico::DomainAccess.authorize_resource!(@context.access, 'JrcRelationship::Survey', survey_id)
    authorize_survey_source!
  end

  def authorize_survey_source!
    raise Pundit::NotAuthorizedError unless @survey.source_type == @ticket.class.name && @survey.source_id == @ticket.id
  end

  def authorized_decision
    id = @evidence['survey_decision_id']
    return unless id

    decision = JrcRelationship::SurveyDispatchDecision.where(account_id: @context.account.id,
                                                             source_type: @ticket.class.name, source_id: @ticket.id).find(id)
    raise Pundit::NotAuthorizedError if @evidence['cycle_key'] && decision.cycle_key != @evidence['cycle_key']
    raise Pundit::NotAuthorizedError if @evidence['survey_id'] && decision.survey_id != @evidence['survey_id']

    decision
  end

  def authorize_recovery!
    id = @evidence['existing_recovery_id'] || @evidence['survey_recovery_id']
    return unless id

    raise Pundit::NotAuthorizedError unless @survey && @survey.metadata['recovery_risk_id'].to_s == id.to_s

    JrcNico::DomainAccess.authorize_resource!(@context.access, 'JrcRelationship::RiskCase', id)
  end
end
