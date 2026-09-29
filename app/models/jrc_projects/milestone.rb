module JrcProjects
  class Milestone < ApplicationRecord
    validates :status, inclusion: { in: %w[open completed canceled] }
    belongs_to :account
    belongs_to :project
    belongs_to :phase, optional: true
    validates :name, presence: true
    validate :phase_belongs_to_project

    private

    def phase_belongs_to_project
      errors.add(:phase, 'deve pertencer ao projeto') if phase && phase.project_id != project_id
    end
  end
end
