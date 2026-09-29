module JrcProjects
  class Recurrence < ApplicationRecord
    belongs_to :account
    belongs_to :project
    validates :frequency, inclusion: { in: %w[daily weekly monthly] }
    validates :interval, numericality: { greater_than: 0 }
    validate { errors.add(:project, 'must belong to account') if project && project.account_id != account_id }
  end
end
