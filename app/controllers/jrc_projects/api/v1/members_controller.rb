module JrcProjects::Api::V1
  class MembersController < ResourceController
    self.catalog_model = JrcProjects::ProjectMember
    self.required_capability = 'projects.member.manage'
    self.permitted_attributes = %i[user_id role allocation_percent]
  end
end
