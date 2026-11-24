# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::ManagerialReportExportsController < Api::V1::Accounts::JrcServiceDesk::ReportExportsController
  before_action :require_managerial_export!

  private

  def report_kind
    'managerial'
  end

  def export_query(filters)
    context = ::JrcServiceDesk::OperationalContext.new(pundit_user)
    parameters = ::JrcServiceDesk::Input.attributes(filters, ::JrcServiceDesk::ManagerialReportQuery::FIELDS)
    ::JrcServiceDesk::ManagerialReportQuery.new(context, parameters.fetch('unit_id'), parameters: parameters, action: :export)
  end

  def require_managerial_export!
    context = ::JrcServiceDesk::OperationalContext.new(pundit_user)
    raise Pundit::NotAuthorizedError unless context.managerial_reporting_allowed?(:export)
  end
end
