# frozen_string_literal: true

class JrcServiceDesk::OlaClock < JrcServiceDesk::TicketRecord
  belongs_to :queue, class_name: 'JrcServiceDesk::Queue'
  belongs_to :sla_snapshot, class_name: 'JrcServiceDesk::SlaSnapshot', optional: true
  validates :state, inclusion: { in: %w[running paused completed stopped] }
  validates :time_basis, inclusion: { in: %w[calendar business] }
  validates :budget_seconds, numericality: { only_integer: true, greater_than: 0 }
  validates :elapsed_seconds, numericality: { greater_than_or_equal_to: 0 }
  validates :started_at, :anchor_at, :due_at, :policy_revision, presence: true
  validates :pause_waiting, inclusion: { in: [true, false] }
  validate :scoped_references

  protected

  def ownership_columns
    super + %i[queue_id sla_snapshot_id budget_seconds time_basis pause_waiting policy_revision started_at escalation_snapshot]
  end

  private

  def scoped_references
    validate_unit_reference(:queue)
    validate_unit_reference(:sla_snapshot)
    errors.add(:sla_snapshot, 'must match ticket') if sla_snapshot && sla_snapshot.ticket_id != ticket_id
    errors.add(:sla_snapshot, 'required for business time') if time_basis == 'business' && !sla_snapshot
  end
end
