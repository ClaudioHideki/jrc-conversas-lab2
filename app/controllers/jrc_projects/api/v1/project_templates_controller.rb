module JrcProjects::Api::V1
  class ProjectTemplatesController < ResourceController
    self.catalog_model=JrcProjects::ProjectTemplate; self.required_capability='projects.template.manage'; self.permitted_attributes=[:name, :version, :active, { definition: {} }]
  end
end
