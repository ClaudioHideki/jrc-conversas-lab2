class JrcMigrations::Adapters::ProjectTaskAttachment < JrcMigrations::Adapters::ProjectAttachment
  private

  def parent_model
    JrcProjects::Task
  end

  def parent_field
    'task_id'
  end

  def parent_legacy_field
    'task_legacy_id'
  end

  def parent_domain
    'project_tasks'
  end
end
