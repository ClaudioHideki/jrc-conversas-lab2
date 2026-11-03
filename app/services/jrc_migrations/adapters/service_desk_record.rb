class JrcMigrations::Adapters::ServiceDeskRecord < JrcMigrations::Adapters::Base
  def candidates(_data)
    []
  end

  private

  def validation_context(record)
    record.persisted? ? [:update, :historical_migration] : :historical_migration
  end

  def resolve_ticket!(record, data)
    bind_legacy_reference!(record, data, field: 'ticket_id', legacy_field: 'ticket_legacy_id', domain: 'service_desk_tickets')
  end

  def assign_historical_times!(record, data, fields)
    fields.each do |field|
      record.public_send("#{field}=", timestamp!(data[field])) if data[field].present?
    end
  end
end
