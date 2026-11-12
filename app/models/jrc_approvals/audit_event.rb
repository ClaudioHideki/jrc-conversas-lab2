class JrcApprovals::AuditEvent < ApplicationRecord
  include JrcApprovals::Immutable
  self.table_name = 'jrc_approvals_audit_events'
  belongs_to :account
  belongs_to :actor, class_name: 'AccountUser'
  validates :event_type, :correlation_key, :data, presence: true
  after_create :prepare_internal_notification

  private

  def prepare_internal_notification
    return unless JrcApprovals::Notifications::EVENTS.include?(event_type)

    JrcApprovals::NotificationOutbox.create!(account_id: account_id, source_event: self)
  end
end
