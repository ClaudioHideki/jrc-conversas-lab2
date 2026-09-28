# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::UiContextController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  def show
    authorize :service_desk, :show?, policy_class: ::JrcServiceDesk::ModulePolicy
    raise ArgumentError unless query_values.empty?
    render json: ::JrcServiceDesk::UiContextService.new(user_context: pundit_user).call
  end
end
