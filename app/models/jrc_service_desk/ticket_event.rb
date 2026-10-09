# frozen_string_literal: true

class JrcServiceDesk::TicketEvent < JrcServiceDesk::TicketRecord
  include JrcServiceDesk::AppendOnly

  TYPES = %w[operational_rule_applied clock_threshold_reached clock_violated approval_escalated resource_linked resource_updated resource_archived
             first_response_recorded ticket_auto_routed notification_delivery_updated notification_resend_requested interaction_republished
             task_created task_updated approval_requested approval_decided incident_linked incident_updated ticket_claimed ticket_created
             ticket_updated ticket_assigned ticket_transferred note_added conversation_linked sla_snapshot_recorded creation_context_recorded
             lifecycle_policy_bound lifecycle_transitioned].freeze

  belongs_to :actor_membership, class_name: 'JrcServiceDesk::UnitMembership', optional: false
  validates :visibility, inclusion: { in: JrcServiceDesk::InteractionVisibility::VALUES }
  validates :event_type, inclusion: { in: TYPES }
  validates :correlation_id, length: { maximum: 120 }, allow_nil: true
  validate :actor_scope_is_consistent
  validate :payload_is_safe_json
  before_create :capture_notification_fields
  after_create_commit :schedule_notification_event

  private

  def capture_notification_fields
    return unless JrcServiceDesk::NotificationEvent.active?(self)

    self.data = data.merge('notification_fields' => JrcServiceDesk::NotificationSource.new(self).current_fields)
  end

  def schedule_notification_event
    JrcServiceDesk::NotificationEventJob.perform_later(id) if JrcServiceDesk::NotificationEvent.active?(self)
  end

  def actor_scope_is_consistent
    validate_unit_reference(:actor_membership)
    validate_active_reference(:actor_membership)
  end

  def payload_is_safe_json
    raise ArgumentError unless data.is_a?(Hash)

    JrcServiceDesk::CanonicalJson.dump(data)
  rescue ArgumentError
    errors.add(:data, 'must be a bounded JSON object')
  end
end
