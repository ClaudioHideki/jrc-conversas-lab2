# frozen_string_literal: true

# Incident-owned facts; never a TicketEvent attached to an unrelated customer.
class JrcServiceDesk::IncidentEntry < JrcServiceDesk::UnitRecord
  include JrcServiceDesk::AppendOnly
  EVENTS = %w[created updated transitioned reopened tickets_linked ticket_unlinked incidents_linked incident_unlinked note_added attachment_added
              attachment_withdrawn].freeze
  belongs_to :incident, class_name: 'JrcServiceDesk::Incident'
  belongs_to :actor_membership, class_name: 'JrcServiceDesk::UnitMembership'
  has_many_attached :files
  after_create_commit :schedule_security_scan
  validates :event_type, inclusion: { in: EVENTS }
  validates :body, length: { maximum: 20_000 }
  validates :idempotency_key, presence: true, length: { maximum: 120 }, uniqueness: { scope: %i[account_id unit_id incident_id actor_membership_id] }
  validates :request_fingerprint, format: { with: /\A[a-f0-9]{64}\z/ }
  validate do
    validate_unit_reference(:incident)
    validate_actor_reference(:actor_membership)
    errors.add(:data, 'must be an object') unless data.is_a?(Hash)
  end

  def schedule_security_scan
    JrcServiceDesk::AttachmentScanJob.perform_later(id) if files.attached?
    return unless data['attachment_rescan_entry_id']

    JrcServiceDesk::AttachmentScanJob.perform_later(data['attachment_rescan_entry_id'], true,
                                                    data['attachment_id'])
  end

  # ActiveStorage scan metadata must not rewrite an immutable event.
  def touch(*)
    true
  end

  def touch_later(*)
    nil
  end
end
