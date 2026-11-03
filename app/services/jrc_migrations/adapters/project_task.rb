class JrcMigrations::Adapters::ProjectTask < JrcMigrations::Adapters::Base
  def model
    JrcProjects::Task
  end

  def candidates(_data)
    # Titles are not identities: distinct tasks can share a title in one project.
    []
  end

  private

  def assignable_attributes
    super + ['labels']
  end

  def resolve_relations!(record, data)
    bind_legacy_reference!(record, data, field: 'project_id', legacy_field: 'project_legacy_id', domain: 'projects')
    bind_legacy_reference!(record, data, field: 'parent_id', legacy_field: 'parent_legacy_id', domain: 'project_tasks')
  end
end
