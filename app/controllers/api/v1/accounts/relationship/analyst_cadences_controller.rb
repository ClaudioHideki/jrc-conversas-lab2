class Api::V1::Accounts::Relationship::AnalystCadencesController < Api::V1::Accounts::Relationship::BaseController
  wrap_parameters false
  before_action { response.headers['Cache-Control'] = 'no-store' }

  def index
    render json: JrcRelationship::AnalystCadences.new(relationship_context).call(params[:analyst_id], page: params.fetch(:page, 1))
  end

  def cancel
    raise ArgumentError, 'Unexpected team cadence fields' unless (request.request_parameters.keys - %w[reason expected_revision]).empty?

    render json: JrcRelationship::ReviewedCadence.new(relationship_context).cancel_for_team(
      analyst_id: params[:analyst_id], id: params[:id], expected_revision: params.require(:expected_revision), reason: params.require(:reason)
    )
  end
end
