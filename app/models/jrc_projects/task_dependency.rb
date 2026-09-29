module JrcProjects
  class TaskDependency < ApplicationRecord
    belongs_to :account
    belongs_to :predecessor, class_name: 'JrcProjects::Task'
    belongs_to :successor, class_name: 'JrcProjects::Task'
    validates :predecessor_id, uniqueness: { scope: :successor_id }
    validates :kind, inclusion: { in: ['finish_to_start'] }
    validate do
      errors.add(:successor, 'deve ser outra tarefa do mesmo projeto') if predecessor && successor && (predecessor_id == successor_id || predecessor.project_id != successor.project_id)
    end
  end
end
