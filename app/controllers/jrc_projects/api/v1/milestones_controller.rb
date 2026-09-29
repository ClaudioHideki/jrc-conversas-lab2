module JrcProjects::Api::V1
  class MilestonesController < ResourceController
    self.catalog_model=JrcProjects::Milestone; self.required_capability='projects.milestone.manage'; self.permitted_attributes=%i[phase_id name due_on status]
  end
end
