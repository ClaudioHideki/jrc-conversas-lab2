# Accepting historical evidence for consultation never authorizes a retroactive
# survey. Native events created later on the same migrated ticket remain valid.
module JrcRelationship::SurveyEventSource
  def self.operational(events)
    imported = JrcMigrations::Mapping.where(domain: 'service_desk_events')
                                     .where('jrc_migration_mappings.account_id = jrc_service_desk_ticket_events.account_id')
                                     .select(:target_id)
    events.where.not(id: imported)
  end

  def self.operational?(event)
    operational(JrcServiceDesk::TicketEvent.where(account_id: event.account_id, id: event.id)).exists?
  end
end
