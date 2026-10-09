# frozen_string_literal: true

# Legacy interactions remain internal. Explicit V2 publications are append-only.
class JrcServiceDesk::TicketNote < JrcServiceDesk::TicketRecord
  include JrcServiceDesk::AppendOnly

  belongs_to :author_membership, class_name: 'JrcServiceDesk::UnitMembership', optional: false
  belongs_to :audience_team, class_name: '::Team', optional: true
  belongs_to :previous_note, class_name: 'JrcServiceDesk::TicketNote', optional: true
  has_many_attached :files

  validates :idempotency_key, presence: true, length: { maximum: 120 },
                              uniqueness: { scope: %i[account_id unit_id ticket_id author_membership_id] }
  validates :request_fingerprint, format: { with: /\A[a-f0-9]{64}\z/ }
  validates :body, presence: true, length: { maximum: 50_000 }
  validates :visibility, inclusion: { in: JrcServiceDesk::InteractionVisibility::VALUES }
  validates :notification_state, inclusion: { in: %w[not_requested requested blocked_activation] }
  validate :publication_is_consistent
  validate :author_scope_is_consistent

  # ActiveStorage touches its record when a blob's scan metadata changes. An
  # append-only interaction has no timestamp update to perform; its payload and
  # creation timestamp remain immutable even while the attachment is scanned.
  def touch(*)
    true
  end

  def touch_later(*)
    nil
  end

  private

  def publication_is_consistent
    JrcServiceDesk::InteractionVisibility.attributes('visibility' => visibility, 'audience_team_id' => audience_team_id,
                                                     'notification_channels' => notification_channels)
    validate_account_reference(:audience_team)
    validate_unit_reference(:previous_note) if previous_note
    errors.add(:previous_note, 'must belong to the same ticket') if previous_note && previous_note.ticket_id != ticket_id
    errors.add(:publication_reason, 'is required for a new publication') if previous_note && publication_reason.blank?
  rescue ArgumentError
    errors.add(:visibility, 'requires a consistent audience and notification policy')
  end

  def author_scope_is_consistent
    validate_unit_reference(:author_membership)
    validate_active_reference(:author_membership)
  end
end
