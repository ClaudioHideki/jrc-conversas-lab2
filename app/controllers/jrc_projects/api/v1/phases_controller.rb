class JrcProjects::Api::V1::PhasesController < JrcProjects::Api::V1::ResourceController
  self.catalog_model = JrcProjects::Phase
  self.required_capability = 'projects.project.update'
  self.permitted_attributes = %i[name position starts_on ends_on]
end
