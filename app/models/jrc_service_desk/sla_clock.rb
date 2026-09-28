# frozen_string_literal: true

class JrcServiceDesk::SlaClock < JrcServiceDesk::TicketRecord
  belongs_to :sla_cycle, class_name: 'JrcServiceDesk::SlaCycle', optional: false
  validates :kind, inclusion: { in: JrcServiceDesk::LifecycleRules::CLOCKS }, uniqueness: { scope: :sla_cycle_id }
  validates :state, inclusion: { in: %w[running paused completed stopped] }
  validates :budget_seconds, numericality: { only_integer: true, greater_than: 0 }
  validates :elapsed_seconds, numericality: { greater_than_or_equal_to: 0 }
  validates :anchor_at, :due_at, :calculator_version, presence: true
  validate :integrity

  def met?
    state == 'completed' && achieved_at ? achieved_at <= due_at : nil
  end

  protected

  def ownership_columns
    super + %i[sla_cycle_id kind budget_seconds calculator_version]
  end

  private

  def integrity
    validate_unit_reference(:sla_cycle)
    errors.add(:sla_cycle, 'must belong to the same ticket') unless sla_cycle&.ticket_id == ticket_id
    errors.add(:achieved_at, 'must match completion state') unless (state == 'completed') == !achieved_at.nil?
  end
end
