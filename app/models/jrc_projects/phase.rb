module JrcProjects
  class Phase < ApplicationRecord
    belongs_to :account
    belongs_to :project
    validates :name, presence: true
  end
end
