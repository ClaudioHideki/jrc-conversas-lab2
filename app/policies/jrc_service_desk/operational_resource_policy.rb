# frozen_string_literal: true

class JrcServiceDesk::OperationalResourcePolicy < JrcServiceDesk::OperationalPolicy
  def index?
    any_unit_allowed? && capability?(:incidents_manage)
  end

  def show?
    record_unit_allowed? && capability?(:incidents_manage)
  end

  alias create? show?
  alias update? show?
  alias destroy? show?

  class Scope < JrcServiceDesk::OperationalPolicy::Scope
    def resolve
      operational_context.capability?(:incidents_manage) ? unit_scope : scope.none
    end
  end
end
