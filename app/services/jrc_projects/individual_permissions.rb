# frozen_string_literal: true

# Module-specific limits intersect the existing project role and CustomRole.
class JrcProjects::IndividualPermissions
  READ_ALIASES = {
    'projects.task.assign' => 'projects.task.update',
    'projects.planning.view' => 'projects.project.view',
    'projects.member.view' => 'projects.project.view',
    'projects.time_entry.view' => 'projects.project.view',
    'projects.attachment.view' => 'projects.project.view'
  }.freeze

  def self.validate!(values)
    raise ArgumentError, 'Project permissions must be an object' unless values.is_a?(Hash)

    allowed = JrcProjects::Authorization::OWNER + %w[projects.project.create projects.template.manage]
    valid = (values.keys - allowed).empty? && values.values.all? { |value| [true, false].include?(value) }
    raise ArgumentError, 'Unsupported project permission' unless valid

    values
  end

  def self.allowed?(member, capability)
    values = member.jrc_projects_permissions
    return values[capability] if values.key?(capability)

    capability != 'projects.project.create'
  end
end
