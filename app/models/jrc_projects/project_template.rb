module JrcProjects
  class ProjectTemplate < ApplicationRecord
    belongs_to :account
    validates :name, :version, presence: true
  end
end
