class JrcApprovals::AuditEvent < ApplicationRecord
  include JrcApprovals::Immutable
  self.table_name = 'jrc_approvals_audit_events'
  belongs_to :account
  belongs_to :actor, class_name: 'AccountUser'
  validates :event_type, :correlation_key, :data, presence: true
end
