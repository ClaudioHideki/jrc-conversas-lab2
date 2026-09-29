module JrcProjects
  class Budget < ApplicationRecord
    validates :planned_cents, :committed_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :currency, inclusion: { in: %w[BRL] }
    belongs_to :account
    belongs_to :project
    validates :currency, presence: true
  end
end
