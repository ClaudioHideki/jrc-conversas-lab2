module JrcProjects
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
    include JrcOperations::AccountScopedRecord
    self.table_name_prefix = 'jrc_projects_'
  end
end
