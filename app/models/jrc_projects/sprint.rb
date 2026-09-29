module JrcProjects
  class Sprint < ApplicationRecord
    validates :status, inclusion: { in: %w[planned active completed] }
    belongs_to :account
    belongs_to :project
    validate { errors.add(:ends_on, 'anterior ao inicio') if starts_on && ends_on && ends_on < starts_on }
    validates :name, presence: true
  end
end
