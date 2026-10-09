# frozen_string_literal: true

class JrcServiceDesk::LifecyclePause < JrcServiceDesk::TicketRecord
  belongs_to :lifecycle_policy_version, class_name: 'JrcServiceDesk::LifecyclePolicyVersion', optional: false
  belongs_to :sla_cycle, class_name: 'JrcServiceDesk::SlaCycle', optional: true
  belongs_to :started_by_membership, class_name: 'JrcServiceDesk::UnitMembership', optional: false
  belongs_to :ended_by_membership, class_name: 'JrcServiceDesk::UnitMembership', optional: true
  validates :reason_code, :started_at, presence: true
  validate :integrity

  protected

  def ownership_columns
    super + %i[lifecycle_policy_version_id sla_cycle_id reason_code clocks started_at started_by_membership_id]
  end

  private

  def integrity
    %i[lifecycle_policy_version sla_cycle started_by_membership ended_by_membership].each { |name| validate_unit_reference(name) }
    errors.add(:sla_cycle, 'must belong to the same ticket') if sla_cycle && sla_cycle.ticket_id != ticket_id
    kinds = lifecycle_policy_version&.rules&.clock_kinds || JrcServiceDesk::LifecycleRules::CLOCKS
    errors.add(:clocks, 'must be an explicit supported list') unless clocks.is_a?(Array) && clocks.uniq == clocks && (clocks - kinds).empty?
    errors.add(:ended_at, 'invalid pause end') unless (ended_at.nil? && ended_by_membership_id.nil?) || (ended_at && ended_by_membership_id && started_at && ended_at >= started_at)
    errors.add(:ended_at, 'cannot rewrite a closed pause') if persisted? && ended_at_in_database && (will_save_change_to_ended_at? || will_save_change_to_ended_by_membership_id?)
  end
end
