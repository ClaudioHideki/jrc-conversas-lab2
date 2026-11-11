# frozen_string_literal: true

class JrcServiceDesk::ServicePolicy < JrcServiceDesk::ConfigurationPolicy
  def show?
    super && (record.new_record? || !JrcServiceDesk::EmployeeAccess.restricted?(operational_context) ||
      JrcServiceDesk::EmployeeAccess.service_ids(operational_context, unit_id: record.unit_id).include?(record.id))
  end

  class Scope < JrcServiceDesk::ConfigurationPolicy::Scope
    def resolve
      return super if operational_context.administrator? && !operational_context.employee_portal?

      JrcServiceDesk::EmployeeAccess.services(super, operational_context)
    end
  end
end
