# frozen_string_literal: true

class JrcServiceDesk::CaseResourceLink < JrcServiceDesk::UnitRecord
  belongs_to :incident, class_name: 'JrcServiceDesk::Incident'
  belongs_to :created_by_membership, class_name: 'JrcServiceDesk::UnitMembership'
  belongs_to :project, class_name: 'JrcProjects::Project', optional: true
  belongs_to :task, class_name: 'JrcProjects::Task', optional: true
  belongs_to :article, optional: true
  belongs_to :approval_request, class_name: 'JrcApprovals::Request', optional: true
  validate do
    validate_unit_reference(:incident)
    validate_actor_reference(:created_by_membership)
    %i[project task article approval_request].each { |key| validate_account_reference(key) }
    errors.add(:base, 'one native target required') unless [task, article, approval_request].compact.one?
    errors.add(:task, 'must belong to project') if task && task.project_id != project_id
    if approval_request && (approval_request.resource_type != incident.class.name || approval_request.resource_id != incident_id)
      errors.add(:approval_request, 'must approve this case')
    end
  end

  protected

  def ownership_columns
    super + %i[incident_id created_by_membership_id project_id task_id article_id approval_request_id]
  end
end
