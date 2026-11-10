# Only serialize records from Customer360.sources, which already applies the
# owning module's policies. Never serialize model payloads or private content.
class JrcCustomers::RecordSerializer
  FIELDS = %w[id display_id title name status created_at updated_at contact_id company_id deal_id lead_id
              requester_id unit_id status_id priority_id project_id key due_on starts_on contract_number order_number
              due_at completed_at direction duration_seconds provider started_at campaign_id sent_at value_cents total_cents proposal_number].freeze

  def call(records)
    records.map do |record|
      row = record.attributes.slice(*FIELDS)
      if record.is_a?(JrcServiceDesk::Ticket)
        row['status'] = record.status.name
        row['phase'] = record.status.phase
      end
      row
    end
  end
end
