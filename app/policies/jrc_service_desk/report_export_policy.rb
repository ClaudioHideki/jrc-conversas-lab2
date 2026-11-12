# frozen_string_literal: true

class JrcServiceDesk::ReportExportPolicy < JrcServiceDesk::OperationalPolicy
  def index?
    operational_context.reporting_allowed?(permission: 'reports_export')
  end

  def create?
    context = operational_context
    record.account_id == context.account.id && record.account_user_id == context.account_user.id &&
      context.reporting_allowed?(permission: 'reports_export', unit: record.unit)
  end

  def show?
    record.persisted? && create?
  end

  class Scope < JrcServiceDesk::OperationalPolicy::Scope
    def resolve
      context = operational_context
      return scope.none unless context.reporting_allowed?(permission: 'reports_export')

      units = context.unit_scope.select { |unit| context.reporting_allowed?(permission: 'reports_export', unit: unit) }.map(&:id)
      scope.where(account_id: context.account.id, account_user_id: context.account_user.id, unit_id: units)
    end
  end
end
