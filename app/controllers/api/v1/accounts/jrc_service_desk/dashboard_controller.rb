# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::DashboardController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  def show
    authorize :service_desk, :dashboard?, policy_class: ::JrcServiceDesk::ModulePolicy
    render json: base_payload.merge(dashboard: ::JrcServiceDesk::DashboardService.new(user_context: pundit_user).call(parameters: query_values))
  end
end
