module JrcProjects
  class Capacity < ApplicationRecord
    belongs_to :account
    belongs_to :user
    validates :minutes_per_day, numericality: { greater_than_or_equal_to: 0 }
  end
end
