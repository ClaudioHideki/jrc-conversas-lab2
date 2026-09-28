# frozen_string_literal: true

class JrcServiceDesk::UnitPolicy < JrcServiceDesk::OperationalPolicy
  def index?
    any_unit_allowed? && capability?(:lookups_view)
  end

  def show?
    context = operational_context
    context.capability?(:lookups_view) && context.unit_allowed?(record)
  end

  # No implicit bootstrap, global administration or self-grant command.
  class Scope < JrcServiceDesk::OperationalPolicy::Scope
    def resolve
      context = operational_context
      return scope.none unless context.capability?(:lookups_view)

      scope.where(account_id: context.account.id, id: context.unit_scope.select(:id))
    end
  end
end
