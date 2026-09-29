module JrcProjects
  class ChecklistItem < ApplicationRecord
    belongs_to :account
    belongs_to :task
    validates :text, presence: true
  end
end
