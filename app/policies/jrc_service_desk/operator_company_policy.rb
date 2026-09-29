# frozen_string_literal: true

class JrcServiceDesk::OperatorCompanyPolicy < JrcServiceDesk::OperationalPolicy
  def index?
    any_unit_allowed? && capability?(:lookups_view)
  end

  def show?
    context = operational_context
    context.capability?(:lookups_view) && context.record_in_account?(record) &&
      context.view_unit_scope.exists?(operator_company_id: record.id)
  end

  class Scope < JrcServiceDesk::OperationalPolicy::Scope
    def resolve
      context = operational_context
      return scope.none unless context.capability?(:lookups_view)

      scope.where(account_id: context.account.id, id: context.view_unit_scope.select(:operator_company_id))
    end
  end
end
