# frozen_string_literal: true

class JrcServiceDesk::CaseLink < JrcServiceDesk::UnitRecord
  belongs_to :incident, class_name: 'JrcServiceDesk::Incident'
  belongs_to :related_incident, class_name: 'JrcServiceDesk::Incident', optional: true
  belongs_to :ticket, class_name: 'JrcServiceDesk::Ticket', optional: true
  belongs_to :created_by_membership, class_name: 'JrcServiceDesk::UnitMembership'
  scope :active, -> { where(active: true) }
  validate do
    %i[incident related_incident ticket created_by_membership].each { |name| validate_unit_reference(name) }
    errors.add(:base, 'one target required') unless ticket_id.nil? != related_incident_id.nil?
    if related_incident && !(incident&.resource_kind == 'problem' && related_incident.resource_kind == 'incident')
      errors.add(:related_incident,
                 'must link a problem to an incident')
    end
  end

  protected

  def ownership_columns
    super + %i[incident_id related_incident_id ticket_id created_by_membership_id]
  end
end
