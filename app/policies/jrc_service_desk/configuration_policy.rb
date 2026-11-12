# frozen_string_literal: true

class JrcServiceDesk::ConfigurationPolicy < JrcServiceDesk::OperationalPolicy
  MANAGEMENT = {
    'JrcServiceDesk::Queue' => :queues_manage, 'JrcServiceDesk::Category' => :categories_manage,
    'JrcServiceDesk::Priority' => :priorities_manage, 'JrcServiceDesk::TicketStatus' => :statuses_manage,
    'JrcServiceDesk::Service' => :services_manage, 'JrcServiceDesk::TicketType' => :categories_manage,
    'JrcServiceDesk::LifecyclePolicy' => :lifecycle_policies_manage
  }.freeze

  def manage_index?
    name = record.is_a?(Class) ? record.name : record.class.name
    any_unit_allowed? && capability?(MANAGEMENT.fetch(name, :unknown))
  end

  def index?
    any_unit_allowed? && capability?(:lookups_view)
  end

  def show?
    return false unless record_unit_visible? && capability?(:lookups_view)
    return true unless JrcServiceDesk::EmployeeAccess.restricted?(operational_context)

    record.new_record? || JrcServiceDesk::EmployeeAccess.catalogue(record.class.all, operational_context).exists?(id: record.id)
  end

  def create?
    record_unit_visible? && capability?(MANAGEMENT.fetch(record.class.name, :unknown))
  end

  def update?
    create?
  end

  # Destroy remains denied. No grant/revoke or provisioning endpoint is introduced.
  class Scope < JrcServiceDesk::OperationalPolicy::Scope
    def resolve
      return scope.none unless operational_context.capability?(:lookups_view)

      JrcServiceDesk::EmployeeAccess.catalogue(unit_scope, operational_context)
    end
  end
end
