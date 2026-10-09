# frozen_string_literal: true

class JrcServiceDesk::IncidentPolicy < JrcServiceDesk::OperationalPolicy
  def index?
    any_unit_allowed? && capability?(:incidents_manage)
  end

  def show?
    record_unit_allowed? && capability?(:incidents_manage)
  end

  alias create? show?
  alias update? show?

  class Scope < JrcServiceDesk::OperationalPolicy::Scope
    def resolve
      operational_context.capability?(:incidents_manage) ? unit_scope : scope.none
    end
  end
end
