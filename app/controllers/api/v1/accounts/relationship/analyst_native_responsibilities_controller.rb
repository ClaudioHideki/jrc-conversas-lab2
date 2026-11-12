class Api::V1::Accounts::Relationship::AnalystNativeResponsibilitiesController < Api::V1::Accounts::Relationship::BaseController
  before_action { response.headers['Cache-Control'] = 'no-store' }

  def index
    render json: JrcRelationship::AnalystNativeResponsibilities.new(relationship_context).call(
      params[:analyst_id], kind: params.fetch(:kind, 'project_tasks'), page: params.fetch(:page, 1)
    )
  end
end
