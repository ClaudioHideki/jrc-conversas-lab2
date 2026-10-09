# frozen_string_literal: true

module JrcServiceDesk::ConfigurationResources
  MODELS = {
    'queues' => JrcServiceDesk::Queue, 'categories' => JrcServiceDesk::Category,
    'priorities' => JrcServiceDesk::Priority, 'statuses' => JrcServiceDesk::TicketStatus,
    'services' => JrcServiceDesk::Service, 'ticket_types' => JrcServiceDesk::TicketType
  }.freeze

  def self.model(resource)
    MODELS.fetch(resource.to_s)
  end

  def self.fields(resource, record)
    result = record.attributes.slice(*JrcServiceDesk::ConfigurationContract::FIELDS.fetch(resource.to_s))
    result['portal_access_until'] = record.portal_access_until&.utc&.iso8601(6) if result.key?('portal_access_until')
    result
  end

  def self.revision(resource, record)
    JrcServiceDesk::CanonicalJson.digest('id' => record.id, 'account_id' => record.account_id, 'unit_id' => record.unit_id,
      'fields' => fields(resource, record), 'updated_at' => record.updated_at&.iso8601(6))
  end

  def self.project(resource, record)
    fields(resource, record).merge('id' => record.id.to_s, 'account_id' => record.account_id.to_s, 'unit_id' => record.unit_id.to_s,
      'revision' => revision(resource, record), 'created_at' => record.created_at&.iso8601(6), 'updated_at' => record.updated_at&.iso8601(6))
  end
end
