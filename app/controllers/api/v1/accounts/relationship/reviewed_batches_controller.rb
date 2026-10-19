class Api::V1::Accounts::Relationship::ReviewedBatchesController < Api::V1::Accounts::Relationship::BaseController
  wrap_parameters false
  before_action :no_store

  def show
    render json: service.get(params[:id])
  end

  def create
    render json: service.preview(body!('ids', 'operation', 'owner_id', 'playbook_id', 'title', 'due_at', 'request_id', 'conversation_id', 'starts_at'))
  end

  def approve
    input = body!('digest')
    result = service.approve(params[:id], digest: input.fetch('digest'))
    JrcRelationship::BatchExecutionJob.perform_later(result.fetch('id')) if result.fetch('state') == 'running'
    render json: result
  end

  def advance
    body!
    render json: service.advance(params[:id])
  end

  def cancel
    body!
    render json: service.cancel(params[:id])
  end

  private

  def service
    JrcRelationship::ReviewedPortfolioBatch.new(relationship_context)
  end

  def body!(*keys)
    input = request.request_parameters
    raise ArgumentError, 'Invalid reviewed batch request' unless (input.keys - keys).empty? && request.query_parameters.empty?

    input
  end

  def no_store
    response.headers['Cache-Control'] = 'no-store'
  end
end
