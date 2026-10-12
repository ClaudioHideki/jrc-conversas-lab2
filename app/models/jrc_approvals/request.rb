class JrcApprovals::Request < ApplicationRecord
  self.table_name = 'jrc_approvals_requests'
  belongs_to :account
  belongs_to :policy_version, class_name: 'JrcApprovals::PolicyVersion'
  belongs_to :requester, class_name: 'AccountUser'
  has_many :decisions, class_name: 'JrcApprovals::Decision', dependent: :restrict_with_exception
  validates :request_key, :resource_type, :input_digest, :fingerprint, :expires_at, presence: true
  validates :state, inclusion: { in: %w[pending approved rejected returned escalated expired canceled stale] }
  attr_readonly :account_id, :policy_version_id, :requester_id, :resource_type, :resource_id, :module_key, :event_key,
                :request_key, :issuer_company_id, :business_unit_id, :snapshot, :stage_plan, :fingerprint, :input_digest, :expires_at
end
