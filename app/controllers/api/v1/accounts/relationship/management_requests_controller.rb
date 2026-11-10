class Api::V1::Accounts::Relationship::ManagementRequestsController < Api::V1::Accounts::Relationship::BaseController
  before_action { response.headers['Cache-Control'] = 'no-store' }
  def index
    render json: service.index(page: params.fetch(:page, 1))
  end
  def resolution_options
    render json: service.resolution_options(id: params[:id], page: params.fetch(:page, 1))
  end
  def create
    values = params.require(:management_request).permit(:kind, :reason, :idempotency_key, :assignment_id, :analyst_id).to_h.symbolize_keys
    render json: service.create!(**values), status: :created
  end
  def route
    values = params.require(:management_request).permit(:expected_version, :batch_review_id, :resolution_event_id).to_h.symbolize_keys
    render json: service.route!(id: params[:id], **values)
  end
  private
  def service
    JrcRelationship::ManagementRequests.new(relationship_context)
  end
end
