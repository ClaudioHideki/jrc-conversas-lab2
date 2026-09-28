# frozen_string_literal: true

class JrcServiceDesk::TicketStatus < JrcServiceDesk::NamedUnitRecord
  PHASES = %w[open waiting resolved closed cancelled].freeze

  has_many :tickets, class_name: 'JrcServiceDesk::Ticket', foreign_key: :status_id, dependent: :restrict_with_error

  validates :phase, inclusion: { in: PHASES }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :initial, inclusion: { in: [true, false] }
  validate :valid_initial_phase
  validate :one_active_initial_status
  validate :phase_cannot_relabel_existing_tickets, on: :update

  private

  def valid_initial_phase
    errors.add(:initial, 'requires open phase') if initial? && phase != 'open'
  end

  def one_active_initial_status
    return unless initial? && active?

    existing = self.class.where(account_id: account_id, unit_id: unit_id, initial: true, active: true)
    existing = existing.where.not(id: id) if persisted?
    errors.add(:initial, 'already exists in this unit') if existing.exists?
  end

  def phase_cannot_relabel_existing_tickets
    return unless will_save_change_to_phase?

    referenced = tickets.exists? || JrcServiceDesk::LifecyclePolicyVersion.where(account_id: account_id, unit_id: unit_id)
      .where('status_phases ? :status_id', status_id: id.to_s).exists?
    errors.add(:phase, 'cannot reinterpret tickets or published policy versions') if referenced
  end
end
