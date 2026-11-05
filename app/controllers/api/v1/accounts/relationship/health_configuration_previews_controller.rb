class Api::V1::Accounts::Relationship::HealthConfigurationPreviewsController < Api::V1::Accounts::Relationship::BaseController
  before_action do
    raise Pundit::NotAuthorizedError unless relationship_context.policy.configure?
  end

  def create
    response.headers['Cache-Control'] = 'no-store'
    render json: JrcRelationship::HealthConfigurationPreview.new(relationship_context).call(
      assignment_id: params.require(:assignment_id), scope_key: params.fetch(:scope_key, 'account'), version: params.require(:version),
      **preview_values
    )
  end

  private

  def preview_values
    %i[weights rules].index_with do |key|
      value = params.require(key)
      raise ArgumentError, 'Configuration weights and rules must be objects' unless value.is_a?(ActionController::Parameters)

      value.to_unsafe_h
    end
  end
end
