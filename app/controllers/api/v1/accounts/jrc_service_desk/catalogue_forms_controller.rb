# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::CatalogueFormsController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  def show
    authorize :lookup, :index?, policy_class: ::JrcServiceDesk::LookupPolicy
    result = ::JrcServiceDesk::CatalogueForm.new(user_context: pundit_user).call(parameters: query_values)
    render json: result
  end
end
