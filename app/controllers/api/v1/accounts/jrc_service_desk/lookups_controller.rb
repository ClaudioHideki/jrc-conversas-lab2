# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::LookupsController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  def index
    authorize :lookup, :index?, policy_class: ::JrcServiceDesk::LookupPolicy
    policy_scope(::JrcServiceDesk::Unit) # Enforce and record Pundit scoped reads.
    query = ::JrcServiceDesk::CatalogQuery.new(user_context: pundit_user, resource: params[:resource], parameters: query_values)
    render json: result_for(query.collection) { |record| presenter.catalog(record, resource: query.resource, unit_id: query.unit_id) }
  end
end
