# frozen_string_literal: true

class JrcServiceDesk::OperationalPolicy < JrcServiceDesk::BasePolicy
  protected

  def operational_context
    # Deliberately not memoized across policy calls: revocation must be rechecked.
    JrcServiceDesk::OperationalContext.new(user_context)
  end

  def capability?(name)
    operational_context.capability?(name)
  end

  def any_unit_allowed?
    context = operational_context
    context.native_operator? && context.unit_scope.exists?
  end

  def record_unit_allowed?
    context = operational_context
    context.native_operator? && context.record_in_account?(record) && context.unit_scope.exists?(id: record.unit_id)
  end

  class Scope < JrcServiceDesk::BasePolicy::Scope
    protected

    def operational_context
      JrcServiceDesk::OperationalContext.new(user_context)
    end

    def unit_scope
      context = operational_context
      return scope.none unless context.native_operator?

      scope.where(account_id: context.account.id, unit_id: context.unit_scope.select(:id))
    end
  end
end
