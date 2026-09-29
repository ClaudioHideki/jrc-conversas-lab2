module JrcProjects::Api::V1
  class RisksController < ResourceController
    self.catalog_model=JrcProjects::Risk; self.required_capability='projects.project.update'; self.permitted_attributes=%i[title description status severity owner_id metadata]
  end
end
