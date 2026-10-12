class JrcApprovals::Decision < ApplicationRecord
  include JrcApprovals::Immutable
  self.table_name = 'jrc_approvals_decisions'
  belongs_to :account
  belongs_to :request, class_name: 'JrcApprovals::Request'
  belongs_to :actor, class_name: 'AccountUser'
  belongs_to :principal, class_name: 'AccountUser'
  belongs_to :delegation, class_name: 'JrcApprovals::Delegation', optional: true
  validates :reason, :step_code, :idempotency_key, :payload_digest, presence: true
  validates :decision, inclusion: { in: JrcApprovals::Definition::ACTIONS }
end
