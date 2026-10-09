# frozen_string_literal: true

# Pure projection of records already selected by PortalScope and native identity.
class JrcServiceDesk::PortalPresenter
  def ticket(record)
    { id: record.id.to_s, number: record.id.to_s, title: record.title, description: record.description,
      status: { name: record.status.name, phase: record.status.phase }, opened_at: record.opened_at.iso8601(6),
      contract_id: record.contract_id&.to_s, service_id: record.service_id&.to_s }
  end

  def service(record, contact: nil)
    catalogue = JrcServiceDesk::PortalCatalogue.new(contact: contact, service: record) if contact
    { id: record.id.to_s, name: record.name, description: record.description,
      form_fields: catalogue ? catalogue.form_fields : record.form_fields,
      contract_required: record.allowed_contract_ids.any?,
      contracts: catalogue ? catalogue.contracts.map { |row| { id: row.id.to_s, name: row.contract_number } } : [],
      revision: JrcServiceDesk::ConfigurationResources.revision('services', record) }
  end

  def note(record)
    { id: record.id.to_s, body: record.body, visibility: record.visibility, created_at: record.created_at.iso8601(6),
      attachments: record.files.map { |attachment| file(attachment) } }
  end

  def customer_message(record)
    { id: record.id.to_s, body: record.content, created_at: record.created_at.iso8601(6),
      attachments: record.attachments.map { |attachment| file(attachment.file, id: attachment.id) } }
  end

  def task(record)
    { id: record.id.to_s, title: record.title, description: record.description, status: record.status,
      due_at: record.due_at&.iso8601(6), checklist: record.checklist }
  end

  private

  def file(attachment, id: attachment.id)
    { id: id.to_s, filename: attachment.filename.to_s,
      scan_state: attachment.blob.metadata['service_desk_scan_state'] || 'unavailable' }
  end
end
