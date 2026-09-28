# frozen_string_literal: true

class JrcServiceDesk::SlaCycle < JrcServiceDesk::TicketRecord
  include JrcServiceDesk::AppendOnly
  belongs_to :lifecycle_policy_version, class_name: 'JrcServiceDesk::LifecyclePolicyVersion', optional: false
  belongs_to :sla_snapshot, class_name: 'JrcServiceDesk::SlaSnapshot', optional: false
  has_many :sla_clocks, class_name: 'JrcServiceDesk::SlaClock', dependent: :restrict_with_error
  validates :number, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: %i[account_id unit_id ticket_id] }
  validates :started_at, presence: true
  validate :integrity

  private

  def integrity
    validate_unit_reference(:lifecycle_policy_version)
    validate_unit_reference(:sla_snapshot)
    errors.add(:sla_snapshot, 'must belong to the same ticket') unless sla_snapshot&.ticket_id == ticket_id
    errors.add(:lifecycle_policy_version, 'must match ticket binding') unless ticket&.lifecycle_policy_version_id == lifecycle_policy_version_id
  end
end
