# frozen_string_literal: true

# Each capability is additional to the native scope AND the applicable lifecycle policy.
class JrcServiceDesk::LifecycleActionPolicy < JrcServiceDesk::TicketPolicy
  def inspect?
    show? && capability?(:sla_view) && capability?(:history_view)
  end

  def action?(action)
    key = JrcServiceDesk::Capabilities::LIFECYCLE_ACTIONS[action.to_s]
    inspect? && record_unit_allowed? && key && capability?(key) && JrcServiceDesk::LifecycleSelector.new(record).applicable.present? || false
  end

  def requirements_allowed?(requirements)
    protected_required = requirements.values_at('note', 'solution', 'evidence').any? ||
      requirements.fetch('fields', {}).values.any? { |spec| spec['required'] }
    !protected_required || view_notes?
  end

  def apply?
    inspect? && JrcServiceDesk::Capabilities::LIFECYCLE_ACTIONS.keys.any? { |action| action?(action) }
  end
end
