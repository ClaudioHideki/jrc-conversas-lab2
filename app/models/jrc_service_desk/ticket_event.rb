# frozen_string_literal: true

class JrcServiceDesk::TicketEvent < JrcServiceDesk::TicketRecord
  include JrcServiceDesk::AppendOnly

  TYPES = %w[ticket_created ticket_updated ticket_assigned ticket_transferred note_added conversation_linked sla_snapshot_recorded creation_context_recorded lifecycle_policy_bound lifecycle_transitioned].freeze

  belongs_to :actor_membership, class_name: 'JrcServiceDesk::UnitMembership', optional: false
  validates :event_type, inclusion: { in: TYPES }
  validates :correlation_id, length: { maximum: 120 }, allow_nil: true
  validate :actor_scope_is_consistent
  validate :payload_is_safe_json

  private

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
