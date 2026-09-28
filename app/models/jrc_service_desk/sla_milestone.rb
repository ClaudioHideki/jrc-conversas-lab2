# frozen_string_literal: true

class JrcServiceDesk::SlaMilestone < JrcServiceDesk::TicketRecord
  KINDS = %w[first_response resolution].freeze

  belongs_to :sla_snapshot, class_name: 'JrcServiceDesk::SlaSnapshot', optional: false
  validates :kind, inclusion: { in: KINDS }, uniqueness: { scope: %i[account_id unit_id sla_snapshot_id] }
  validates :calculator_version, length: { maximum: 100 }, allow_nil: true
  validate :snapshot_is_consistent
  validate :calculation_provenance_is_complete

  def calculation_pending?
    due_at.nil?
  end

  # nil means unknown: no calculated deadline must never be shown as SLA met.
  def met?
    return nil if calculation_pending? || achieved_at.nil?

    achieved_at <= due_at
  end

  protected

  def ownership_columns
    super + %i[sla_snapshot_id kind]
  end

  private

  def snapshot_is_consistent
    validate_unit_reference(:sla_snapshot)
    errors.add(:sla_snapshot, 'must reference the same ticket') if sla_snapshot && sla_snapshot.ticket_id != ticket_id
  end

  def calculation_provenance_is_complete
    if due_at.nil?
      errors.add(:due_at, 'is required with calculation metadata') if !calculated_at.nil? || !calculator_version.nil?
    elsif calculated_at.nil? || calculator_version.blank?
      errors.add(:due_at, 'requires calculation time and calculator version')
    end
  end
end
