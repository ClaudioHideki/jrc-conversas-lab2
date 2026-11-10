class JrcApprovals::NotificationOutbox < ApplicationRecord
  self.table_name = 'jrc_approvals_notification_outboxes'
  belongs_to :account
  belongs_to :source_event, class_name: 'JrcApprovals::AuditEvent'
  attr_readonly :account_id, :source_event_id, :created_at
end
