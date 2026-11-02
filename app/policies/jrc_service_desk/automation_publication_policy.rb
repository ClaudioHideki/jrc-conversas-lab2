# frozen_string_literal: true

class JrcServiceDesk::AutomationPublicationPolicy < JrcServiceDesk::OperationalPolicy
  def index?
    any_unit_allowed? && %w[lifecycle operational].any? { |kind| allowed_kind?(kind) }
  end

  def show?
    return false unless record_unit_allowed? && allowed_kind?(record.kind)
    return true unless record.definition

    context = operational_context
    definition = record.definition
    definition.fetch('families', {}).keys.all? { |kind| JrcServiceDesk::OperationalRuleAccess.allowed?(context, kind) } &&
      (definition.fetch('queues', []).empty? || context.capability?(:queues_manage)) &&
      (definition.fetch('notifications', []).empty? || context.capability?(:notifications_manage))
  end
  alias create? show?

  def allowed_kind?(kind)
    context = operational_context
    context.capability?(:settings_view) && if kind == 'lifecycle'
      context.capability?(:lifecycle_policies_manage)
    else
      JrcServiceDesk::OperationalRuleAccess.allowed?(context, 'routing')
    end
  end

  class Scope < JrcServiceDesk::OperationalPolicy::Scope
    def resolve
      kinds = %w[lifecycle operational].select do |kind|
        JrcServiceDesk::AutomationPublicationPolicy.new(operational_context.to_h, JrcServiceDesk::AutomationPublication.new(kind: kind)).allowed_kind?(kind)
      end
      unit_scope.where(kind: kinds, unit_id: operational_context.unit_scope.select(:id))
    end
  end
end
