class Api::V1::Accounts::Relationship::CadencesController < Api::V1::Accounts::Relationship::BaseController
  wrap_parameters false
  before_action :no_store

  def show
    render json: service.get(params[:id])
  end

  def advance
    empty_body!
    render json: service.advance(params[:id])
  end

  def cancel
    empty_body!
    render json: service.cancel(params[:id])
  end

  private

  def service
    JrcRelationship::ReviewedCadence.new(relationship_context)
  end

  def empty_body!
    raise ArgumentError, 'Unexpected cadence fields' unless request.request_parameters.empty? && request.query_parameters.empty?
  end

  def no_store
    response.headers['Cache-Control'] = 'no-store'
  end
end
