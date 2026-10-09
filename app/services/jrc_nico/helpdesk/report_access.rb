# frozen_string_literal: true

class JrcNico::Helpdesk::ReportAccess
  def initialize(member)
    @context = JrcNico::Helpdesk::Context.new(member)
  end

  def authorize!(report)
    @context.refresh!
    raise Pundit::NotAuthorizedError unless report.account_id == @context.account.id && report.recipient_id == @context.member.id

    authorize_tickets!(report)
    authorize_evidence!(report)
    report
  end

  private

  def authorize_tickets!(report)
    reporting = JrcNico::Helpdesk::ReportingScope.new(@context, report.policy_version, report.payload.fetch('filters', {}))
    ids = report.payload.fetch('ticket_ids')
    raise Pundit::NotAuthorizedError unless reporting.tickets.where(id: ids).pluck(:id).sort == ids.sort
  end

  def authorize_evidence!(report)
    report.payload.fetch('visible_event_ids', []).each { |id| @context.event(id) }
    report.payload.fetch('evidence_resources', []).each { |type, id| JrcNico::DomainAccess.authorize_resource!(@context.access, type, id) }
    JrcNico::Helpdesk::ReportResources.new(@context, report.payload).call
  end
end
