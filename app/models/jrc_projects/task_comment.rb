module JrcProjects
  class TaskComment < ApplicationRecord
    belongs_to :account
    belongs_to :task
    belongs_to :user
    validates :body, presence: true
  end
end
