class Api::V1::Accounts::Crm::BackofficeRequirementRulesController < Api::V1::Accounts::Crm::BaseController
  before_action { response.headers['Cache-Control'] = 'no-store' }
  rescue_from JrcBackoffice::RequirementCatalog::Conflict do |error|
    render json: { code: 'REQUIREMENT_RULE_CHANGED', message: error.message }, status: :conflict
  end
  rescue_from ArgumentError, KeyError do |error|
    render json: { message: error.message }, status: :unprocessable_entity
  end

  def capabilities
    render json: { can_manage: JrcBackoffice::SignatureConfiguration.can_manage?(account: Current.account, actor: Current.user) }
  end

  def index
    render json: catalog.index(page: params.fetch(:page, 1), query: params[:q])
  end

  def create
    raise ArgumentError, 'Creation requires revision zero' unless params[:version] == 0

    render json: catalog.save!(rule_key: params.require(:intent), expected_version: params.require(:version), attributes: rule_params, reason: params[:reason]),
           status: :created
  end

  def options
    render json: catalog.options(kind: params[:kind], query: params[:q], page: params.fetch(:page, 1))
  end

  def update
    raise ArgumentError, 'Editing requires a positive revision' unless params[:version].is_a?(Integer) && params[:version].positive?

    render json: catalog.save!(rule_key: params[:id], expected_version: params.require(:version), attributes: rule_params, reason: params[:reason])
  end

  private

  def catalog
    JrcBackoffice::RequirementCatalog.new(account: Current.account, actor: Current.user)
  end

  def rule_params
    input = params.require(:rule)
    raise ArgumentError, 'Rule must be an object' unless input.is_a?(ActionController::Parameters)

    # Keep invalid shapes so the closed validator rejects, rather than turning
    # a filtered-out unit/product array into an accidental account-wide scope.
    input.to_unsafe_h
  end
end
