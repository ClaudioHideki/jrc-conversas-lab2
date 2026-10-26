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

  def work?
    update? && capability?(:work_status_change)
  end

  def resolve?
    update? && capability?(:resolve)
  end

  def close?
    update? && capability?(:close)
  end

  def reopen?
    update? && capability?(:reopen)
  end

  def comment?
    show? && capability?(:notes_add)
  end

  class Scope < JrcServiceDesk::OperationalPolicy::Scope
    def resolve
      operational_context.capability?(:incidents_manage) ? unit_scope : scope.none
    end
  end
end
