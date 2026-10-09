# frozen_string_literal: true

class JrcServiceDesk::OperationalRuleVersionPolicy < JrcServiceDesk::OperationalPolicy
  def index?
    any_unit_allowed? && JrcServiceDesk::OperationalRuleContract::KINDS.any? do |kind|
      JrcServiceDesk::OperationalRuleAccess.allowed?(operational_context, kind)
    end
  end

  def show?
    record_unit_allowed? && JrcServiceDesk::OperationalRuleAccess.allowed?(operational_context, record.kind)
  end

  alias create? show?

  class Scope < JrcServiceDesk::OperationalPolicy::Scope
    def resolve
      context = operational_context
      kinds = JrcServiceDesk::OperationalRuleContract::KINDS.select { |kind| JrcServiceDesk::OperationalRuleAccess.allowed?(context, kind) }
      unit_scope.where(kind: kinds, unit_id: context.unit_scope.select(:id))
    end
  end
end
