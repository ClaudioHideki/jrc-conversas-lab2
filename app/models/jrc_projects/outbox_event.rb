module JrcProjects
  class OutboxEvent < ApplicationRecord
    belongs_to :account
    scope :due, -> { where(status: 'pending').where(available_at: ..Time.current) }
  end
end
