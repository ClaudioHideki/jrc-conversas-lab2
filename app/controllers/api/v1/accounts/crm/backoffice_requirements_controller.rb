class Api::V1::Accounts::Crm::BackofficeRequirementsController < Api::V1::Accounts::Crm::BaseController
  before_action { response.headers['Cache-Control'] = 'no-store' }
  rescue_from JrcBackoffice::Requirements::Conflict do |error|
    render json: { code: 'REQUIREMENTS_CHANGED', message: error.message }, status: :conflict
  end
  rescue_from ArgumentError do |error|
    render json: { message: error.message }, status: :unprocessable_entity
  end

  def index
    render json: service.projection
  end

  def history
    revision = Integer(params.require(:plan_revision).to_s, 10)
    render json: service.response_history(key: params.require(:key), plan_revision: revision, page: params.fetch(:page, 1))
  end

  def adopt
    render json: service.adopt!(expected_revision: params.require(:revision), reason: params[:reason])
  end

  def answer
    input = params.require(:answer)
    raise ArgumentError, 'Answer must be an object' unless input.is_a?(ActionController::Parameters)

    payload = input.to_unsafe_h
    render json: service.answer!(key: params.require(:key), expected_plan_revision: params.require(:plan_revision),
      expected_response_revision: params.require(:response_revision), payload: payload, reason: params[:reason])
  end

  private

  def service
    request = JrcBackoffice::ContractAccess.new(account: Current.account, actor: Current.user).request(params[:backoffice_request_id])
    JrcBackoffice::Requirements.new(request: request, actor: Current.user)
  end
end
