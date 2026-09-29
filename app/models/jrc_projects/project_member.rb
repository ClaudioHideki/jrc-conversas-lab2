module JrcProjects
  class ProjectMember < ApplicationRecord
    ROLES = %w[owner manager member contributor viewer].freeze
    belongs_to :account
    belongs_to :project
    belongs_to :user
    validates :role, inclusion: { in: ROLES }
    validates :user_id, uniqueness: { scope: :project_id }
    validates :allocation_percent, inclusion: { in: 0..100 }
    validate :tenant_consistency

    private

    def tenant_consistency
      errors.add(:project, 'must belong to account') if project && project.account_id != account_id
      errors.add(:user, 'must belong to account') if account && user && !account.users.exists?(user.id)
    end
  end
end
