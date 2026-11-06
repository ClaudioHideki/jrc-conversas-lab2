class Api::V1::Accounts::Relationship::ReviewedBatchesController < Api::V1::Accounts::Relationship::BaseController
  wrap_parameters false
  before_action :no_store
  rescue_from JrcApprovals::Error do |error|
    render json: { errors: [error.code] }, status: :unprocessable_entity
  end

  def show
    render json: service.get(params[:id])
  end

  def create
    render json: service.preview(body!('ids', 'operation', 'owner_id', 'playbook_id', 'title', 'due_at', 'request_id', 'conversation_id', 'starts_at',
                                       'justification', 'transfer_responsibilities', 'portfolio_group_id', 'expected_version',
                                       'active', 'previous_review_id'))
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

  def request_approval
    input = body!('digest', 'idempotency_key')
    render json: service.request_approval(params[:id], digest: input.fetch('digest'), idempotency_key: input.fetch('idempotency_key'))
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
    # Keep null entries visible to the finite native input validators rather
    # than letting Rails silently reduce the reviewed audience.
    input = if request.media_type == 'application/json'
              ActiveSupport::JSON.decode(request.raw_post.presence || '{}')
            else
              request.request_parameters
            end
    valid = input.is_a?(Hash) && (input.keys - keys).empty? && request.query_parameters.empty?
    raise ArgumentError, 'Invalid reviewed batch request' unless valid

    input
  end

  def no_store
    response.headers['Cache-Control'] = 'no-store'
  end
end
