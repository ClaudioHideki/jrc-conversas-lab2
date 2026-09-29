module JrcProjects::Api::V1
  class BoardsController < ResourceController
    self.catalog_model = JrcProjects::Board
    self.required_capability = 'projects.board.manage'
    self.permitted_attributes = %i[name]
  end
end
