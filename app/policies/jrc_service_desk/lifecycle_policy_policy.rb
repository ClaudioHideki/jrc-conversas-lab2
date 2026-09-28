# frozen_string_literal: true

class JrcServiceDesk::LifecyclePolicyPolicy < JrcServiceDesk::ConfigurationPolicy
  def index?
    any_unit_allowed? && capability?(:lifecycle_policies_manage)
  end

  def show?
    record_unit_allowed? && capability?(:lifecycle_policies_manage)
  end

  def publish?
    show?
  end

  def create?
    publish?
  end

  def update?
    publish?
  end

  class Scope < JrcServiceDesk::ConfigurationPolicy::Scope
    def resolve
      return scope.none unless operational_context.capability?(:lifecycle_policies_manage)

      super
    end
  end
end
