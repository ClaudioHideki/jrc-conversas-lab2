class JrcApprovals::Delegation < ApplicationRecord
  self.table_name = 'jrc_approvals_delegations'
  belongs_to :account
  belongs_to :policy_version, class_name: 'JrcApprovals::PolicyVersion'
  %i[grantor principal delegate].each { |name| belongs_to name, class_name: 'AccountUser' }
  attr_readonly :account_id, :policy_version_id, :grantor_id, :principal_id, :delegate_id, :step_code, :actions, :reason, :starts_at, :ends_at
  validates :reason, :starts_at, :ends_at, presence: true
end
