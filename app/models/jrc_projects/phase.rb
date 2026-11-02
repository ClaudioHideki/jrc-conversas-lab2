module JrcProjects
  class Phase < ApplicationRecord
    belongs_to :account
    belongs_to :project
    has_many :milestones, dependent: :restrict_with_error
    validates :name, presence: true
    validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :valid_dates

    private

    def valid_dates
      errors.add(:ends_on, 'anterior ao início') if starts_on && ends_on && ends_on < starts_on
    end
  end
end
