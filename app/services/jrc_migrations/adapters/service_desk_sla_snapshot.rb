class JrcMigrations::Adapters::ServiceDeskSlaSnapshot < JrcMigrations::Adapters::ServiceDeskRecord
  def model
    JrcServiceDesk::SlaSnapshot
  end

  def update_allowed?
    false
  end

  def candidates(data)
    data['ticket_id'].present? ? scope.where(ticket_id: data['ticket_id'], version: data['version']).limit(1).pluck(:id) : []
  end

  private

  def resolve_relations!(record, data)
    resolve_ticket!(record, data)
    assign_historical_times!(record, data, %w[captured_at applied_at])
  end
end
