module JrcProjects
  class Risk < ApplicationRecord
    validates :status, inclusion: { in: %w[open monitoring resolved closed] }
    belongs_to :account
    belongs_to :project
    belongs_to :owner, class_name: 'User', optional: true
    validates :title, presence: true
    validate { errors.add(:owner, 'must belong to account') if owner && !account.users.exists?(owner.id) }
  end
end
