module JrcProjects::Api::V1
  class SprintsController < ResourceController
    self.catalog_model=JrcProjects::Sprint; self.required_capability='projects.project.update'; self.permitted_attributes=%i[name status starts_on ends_on]
  end
end
