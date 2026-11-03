class JrcMigrations::Adapters::ServiceDeskTicket < JrcMigrations::Adapters::ServiceDeskRecord
  def model
    JrcServiceDesk::Ticket
  end

  def candidates(data)
    return [] if data['idempotency_key'].blank?

    scope.where(unit_id: data['unit_id'], created_by_membership_id: data['created_by_membership_id'],
                idempotency_key: data['idempotency_key']).limit(1).pluck(:id)
  end

  private

  def resolve_relations!(record, data)
    bind_legacy_reference!(record, data, field: 'requester_id', legacy_field: 'requester_legacy_id', domain: 'contacts')
    bind_legacy_reference!(record, data, field: 'company_id', legacy_field: 'company_legacy_id')
    check_company!(record.company_id)
    assign_historical_times!(record, data, ['opened_at'])
  end
end
