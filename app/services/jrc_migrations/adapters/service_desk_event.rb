class JrcMigrations::Adapters::ServiceDeskEvent < JrcMigrations::Adapters::ServiceDeskRecord
  def model
    JrcServiceDesk::TicketEvent
  end

  def update_allowed?
    false
  end

  private

  def resolve_relations!(record, data)
    resolve_ticket!(record, data)
    return if record.audience_team_id.blank? || Team.exists?(account_id: account.id, id: record.audience_team_id)

    raise JrcMigrations::Error, 'RELATION_OUTSIDE_ACCOUNT'
  end
end
