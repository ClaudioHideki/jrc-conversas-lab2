# frozen_string_literal: true

# No role, including administrator, receives operational access in CP1.
# Concrete policies and company/unit/queue/record filters belong to later steps.
class JrcServiceDesk::BasePolicy < ApplicationPolicy
  # ApplicationPolicy#show? delegates to a scope. The foundation must deny it too.
  def show?
    false
  end

  protected

  def service_desk_context
    @service_desk_context ||= ::JrcServiceDesk::AccessContext.new(user_context)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.none
    end

    protected

    # A tenant boundary, not the final authorized scope. Concrete scopes MUST
    # also apply the approved company/unit/team/queue/record authorization.
    def account_scope
      context = ::JrcServiceDesk::AccessContext.new(user_context)
      return scope.none unless context.available?

      scope.where(account_id: context.account.id)
    end
  end
end
