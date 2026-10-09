# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::DashboardController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  def show
    authorize :service_desk, :dashboard?, policy_class: ::JrcServiceDesk::ModulePolicy
    render json: base_payload.merge(dashboard: ::JrcServiceDesk::DashboardService.new(user_context: pundit_user).call(parameters: query_values))
  end

  def report
    authorize :service_desk, :dashboard?, policy_class: ::JrcServiceDesk::ModulePolicy
    query = ::JrcServiceDesk::TicketQuery.new(user_context: pundit_user, parameters: query_values)
    render json: result_for(query.collection) { |record| presenter.ticket(record) }.merge(
      dashboard: ::JrcServiceDesk::DashboardService.new(user_context: pundit_user).call(parameters: query_values),
      generated_at: Time.current.iso8601(6), projection: 'authorized_service_desk_report_v2'
    )
  end
end
