module JrcProjects
  class TimeEntry < ApplicationRecord
    validates :status, inclusion: { in: %w[submitted approved rejected] }
    validates :worked_on, presence: true
    validates :minutes, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 1440 }
    validates :hourly_cost_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
    validate :same_project
    validate :project_accepts_new_time, on: :create
    def same_project
      errors.add(:task, 'de outro projeto') if task && task.project_id != project_id
    end
    belongs_to :account
    belongs_to :project
    belongs_to :task, optional: true
    belongs_to :user
    validates :minutes, numericality: { greater_than: 0 }
    validate :task_belongs_to_project

    private

    def project_accepts_new_time
      errors.add(:project, 'deve estar aberto para receber horas') if project && %w[completed canceled].include?(project.status)
    end

    def task_belongs_to_project
      errors.add(:task, 'must belong to project') if task && task.project_id != project_id
    end
  end
end
