# frozen_string_literal: true

module JrcServiceDesk::StructureRecords
  def self.model(resource)
    { 'operator_companies' => JrcServiceDesk::OperatorCompany, 'units' => JrcServiceDesk::Unit,
      'unit_memberships' => JrcServiceDesk::UnitMembership }.fetch(resource.to_s)
  end

  def self.revision(resource, record)
    JrcServiceDesk::CanonicalJson.digest('resource' => resource, 'record' => attributes(resource, record),
      'updated_at' => record.updated_at&.iso8601(6))
  end

  def self.attributes(resource, record)
    record.attributes.slice('id', 'account_id', *JrcServiceDesk::StructureContract::FIELDS.fetch(resource))
  end

  def self.project(resource, record)
    attributes(resource, record).tap do |data|
      data.keys.grep(/(?:\Aid\z|_id\z)/).each { |key| data[key] = data[key]&.to_s }
      data['revision'] = revision(resource, record)
      data['created_at'] = record.created_at&.iso8601(6)
      data['updated_at'] = record.updated_at&.iso8601(6)
    end
  end
end
