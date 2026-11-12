class Api::V1::Accounts::Relationship::AnalystCapacitiesController < Api::V1::Accounts::Relationship::BaseController
  def show
    response.headers['Cache-Control'] = 'no-store'
    render json: JrcRelationship::AnalystCapacity.new(relationship_context).call(
      params[:analyst_id], page: params.fetch(:page, 1), per_page: params.fetch(:per_page, 10)
    )
  end
end
