class JrcApprovals::Policy < ApplicationRecord
  self.table_name = 'jrc_approvals_policies'
  belongs_to :account
  belongs_to :author, class_name: 'AccountUser'
  belongs_to :current_version, class_name: 'JrcApprovals::PolicyVersion', optional: true
  has_many :versions, class_name: 'JrcApprovals::PolicyVersion', dependent: :restrict_with_exception
  validates :code, :name, :module_key, :event_key, presence: true
  validates :code, uniqueness: { scope: :account_id }
  validates :state, inclusion: { in: %w[draft validated published retired] }
  attr_readonly :account_id, :issuer_company_id, :business_unit_id, :module_key, :event_key, :code, :author_id
  validate :organizational_scope

  private

  def organizational_scope
    JrcApprovals::Authorization.scope!(account, issuer_company_id, business_unit_id)
    errors.add(:author, 'must belong to account') unless author.account_id == account_id
  rescue ActiveRecord::RecordNotFound, JrcApprovals::Error
    errors.add(:base, 'invalid organizational scope')
  end
end
