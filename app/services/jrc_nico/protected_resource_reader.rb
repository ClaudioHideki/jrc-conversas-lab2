# Snapshot sources and Service Desk resources keep their native current authorization.
class JrcNico::ProtectedResourceReader
  SOURCES = { 'JrcRelationship::Survey' => 'surveys', 'JrcCrm::Invoice' => 'invoices', 'CsatSurveyResponse' => 'csat',
              'Conversation' => 'conversations', 'Message' => 'messages', 'Call' => 'calls',
              'JrcServiceDesk::TicketEvent' => 'ticket_events', 'JrcProjects::AuditEvent' => 'project_events' }.freeze
  TICKET_MODELS = { 'JrcServiceDesk::TicketNote' => JrcServiceDesk::TicketNote, 'JrcServiceDesk::TicketTask' => JrcServiceDesk::TicketTask,
                    'JrcServiceDesk::TicketApproval' => JrcServiceDesk::TicketApproval }.freeze

  def initialize(access, domain)
    @access = access
    @domain = domain
  end

  def supported?(type)
    SOURCES.key?(type) || TICKET_MODELS.key?(type) || type == 'JrcServiceDesk::Incident'
  end

  def authorize!(type, id)
    return snapshot(type, id) if SOURCES.key?(type)
    return ticket_resource(type, id) if TICKET_MODELS.key?(type)

    incident(id)
  end

  private

  def snapshot(type, id)
    JrcRelationship::SnapshotAccess.sources(JrcRelationship::Context.new(@access.membership)).fetch(SOURCES.fetch(type)).find(id)
  end

  def ticket_resource(type, id)
    record = TICKET_MODELS.fetch(type).where(account_id: @access.account.id).find(id)
    @domain.ticket(record.ticket_id)
    Pundit.authorize(@domain.context, record, :show?)
    record
  end

  def incident(id)
    record = JrcServiceDesk::Incident.where(account_id: @access.account.id).find(id)
    Pundit.authorize(@domain.context, record, :show?)
    record.tickets.each { |linked_ticket| @domain.ticket(linked_ticket.id) }
    record
  end
end
