# frozen_string_literal: true

# Each capability is additional to the native scope AND the applicable lifecycle policy.
class JrcServiceDesk::LifecycleActionPolicy < JrcServiceDesk::TicketPolicy
  def inspect?
    show? && ((capability?(:sla_view) && capability?(:history_view)) || JrcServiceDesk::OperationalClosure.allowed?(user_context, record))
  end

  def action?(action)
    key = JrcServiceDesk::Capabilities::LIFECYCLE_ACTIONS[action.to_s]
    (inspect? && record_unit_allowed? && key && capability?(key) && JrcServiceDesk::LifecycleSelector.new(record).applicable.present?) || false
  end

  def requirements_allowed?(requirements)
    protected_required = requirements.values_at('note', 'solution', 'evidence').any? ||
      requirements.fetch('fields', {}).values.any? { |spec| spec['required'] }
    !protected_required || view_notes?
  end

  def own_closure?(transition)
    JrcServiceDesk::OperationalClosure.allowed?(user_context, record) &&
      transition.ticket_id == record.id && transition.account_id == record.account_id &&
      transition.actor_membership.account_user_id == operational_context.account_user.id &&
      transition.payload['operational_closure'] == true && %w[resolve close].include?(transition.action)
  end

  def apply?
    inspect? && JrcServiceDesk::LifecycleSelector.new(record).applicable.present? && (JrcServiceDesk::OperationalClosure.allowed?(user_context, record) ||
      JrcServiceDesk::Capabilities::LIFECYCLE_ACTIONS.keys.any? { |action| action?(action) })
  end
end
