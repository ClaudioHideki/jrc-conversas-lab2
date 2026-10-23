module JrcProjects
  class AutomationRule < ApplicationRecord
    belongs_to :account
    belongs_to :project, optional: true
    validates :name, :event_name, presence: true
    validate { errors.add(:project, 'deve pertencer à conta') if project && project.account_id != account_id }
  end
end
