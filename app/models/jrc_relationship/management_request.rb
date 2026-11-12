# A request for native management work, not an approval or execution engine.
class JrcRelationship::ManagementRequest < ApplicationRecord
  self.table_name = 'jrc_relationship_management_requests'
  belongs_to :account
  belongs_to :requester, class_name: 'User'
  belongs_to :assignment, class_name: 'JrcRelationship::Assignment', optional: true
  belongs_to :analyst, class_name: 'User', optional: true
  belongs_to :batch_review, class_name: 'JrcRelationship::BatchReview', optional: true
  belongs_to :resolution_event, class_name: 'JrcCrm::AuditEvent', optional: true
  validates :kind, inclusion: { in: %w[transfer suspend restore] }
  validates :state, inclusion: { in: %w[pending routed] }
  validates :reason, length: { minimum: 1, maximum: 2000 }
  validates :idempotency_key, uniqueness: { scope: [:account_id, :requester_id] }, format: { with: /\A[a-zA-Z0-9:_-]{1,120}\z/ }
  validates :input_digest, format: { with: /\A[a-f0-9]{64}\z/ }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Management requests are retained' }
end
