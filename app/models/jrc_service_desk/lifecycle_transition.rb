# frozen_string_literal: true

class JrcServiceDesk::LifecycleTransition < JrcServiceDesk::TicketRecord
  include JrcServiceDesk::AppendOnly
  belongs_to :lifecycle_policy_version, class_name: 'JrcServiceDesk::LifecyclePolicyVersion', optional: false
  belongs_to :actor_membership, class_name: 'JrcServiceDesk::UnitMembership', optional: false
  belongs_to :from_status, class_name: 'JrcServiceDesk::TicketStatus', optional: false
  belongs_to :to_status, class_name: 'JrcServiceDesk::TicketStatus', optional: false
  validates :action, inclusion: { in: JrcServiceDesk::LifecycleRules::ACTIONS }
  validates :rule_key, :request_key, :occurred_at, presence: true
  validates :request_key, length: { maximum: 120 }, uniqueness: { scope: %i[account_id unit_id ticket_id actor_membership_id] }
  validates :fingerprint, format: { with: /\A[a-f0-9]{64}\z/ }
  validate :integrity

  private

  def integrity
    %i[lifecycle_policy_version actor_membership from_status to_status].each { |name| validate_unit_reference(name) }
    errors.add(:lifecycle_policy_version, 'must match ticket binding') unless ticket&.lifecycle_policy_version_id == lifecycle_policy_version_id
    raise ArgumentError unless payload.is_a?(Hash)
    JrcServiceDesk::CanonicalJson.dump(payload)
  rescue ArgumentError
    errors.add(:payload, 'must be bounded JSON')
  end
end
