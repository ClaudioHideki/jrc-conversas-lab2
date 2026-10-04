class Api::V1::Accounts::Customers::TaxonomiesController < Api::V1::Accounts::Customers::BaseController
  before_action :authorize_admin!, except: [:index]
  before_action :set_taxonomy, only: [:update]

  def index
    scope = JrcCustomers::Taxonomy.where(account_id: Current.account.id)
    scope = scope.where(kind: params[:kind]) if params[:kind].present?
    render json: { payload: scope.ordered.as_json(only: %i[id kind name active position created_at updated_at]) }
  end

  def create
    taxonomy = JrcCustomers::Taxonomy.create!(taxonomy_params.merge(account_id: Current.account.id))
    render json: { payload: taxonomy.as_json(only: %i[id kind name active position created_at updated_at]) }, status: :created
  end

  def update
    @taxonomy.update!(taxonomy_params)
    render json: { payload: @taxonomy.as_json(only: %i[id kind name active position created_at updated_at]) }
  end

  private

  def set_taxonomy
    @taxonomy = JrcCustomers::Taxonomy.where(account_id: Current.account.id).find(params[:id])
  end

  def taxonomy_params
    params.require(:taxonomy).permit(:kind, :name, :active, :position)
  end
end
