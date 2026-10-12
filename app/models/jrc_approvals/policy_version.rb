class JrcApprovals::PolicyVersion < ApplicationRecord
  include JrcApprovals::Immutable
  self.table_name = 'jrc_approvals_policy_versions'
  belongs_to :account
  belongs_to :policy, class_name: 'JrcApprovals::Policy'
  belongs_to :publisher, class_name: 'AccountUser'
  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: %i[account_id policy_id] }
  validates :digest, format: { with: /\A[a-f0-9]{64}\z/ }
end
