# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::ManagerialReportsController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  before_action :require_managerial_reports!

  def show
    query = ::JrcServiceDesk::ManagerialReportQuery.new(report_context, query_values.fetch('unit_id'))
    render json: base_payload.merge(unit_id: query.unit.id.to_s, timezone: query.timezone.tzinfo.name, **query.collection(query_values))
  end

  def options
    filters = ::JrcServiceDesk::Input.attributes(query_values, %w[unit_id field q])
    if filters.empty?
      units = report_context.unit_scope.order(:name, :id).filter_map do |unit|
        { id: unit.id.to_s, name: unit.name } if report_context.managerial_reporting_allowed?(unit: unit)
      end
      render json: base_payload.merge(items: units)
      return
    end

    search = filters.fetch('q', '')
    raise ArgumentError unless search.is_a?(String) && search.length <= 100

    query = ::JrcServiceDesk::ManagerialReportQuery.new(report_context, filters.fetch('unit_id'))
    render json: base_payload.merge(unit_id: query.unit.id.to_s, **query.options(filters.fetch('field'), search.strip))
  end

  private

  def report_context
    @report_context ||= ::JrcServiceDesk::OperationalContext.new(pundit_user)
  end

  def require_managerial_reports!
    authorize :module, :dashboard?, policy_class: ::JrcServiceDesk::ModulePolicy
    raise Pundit::NotAuthorizedError unless report_context.managerial_reporting_allowed?
  end
end
