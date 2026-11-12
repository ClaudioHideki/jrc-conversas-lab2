class Api::V1::Accounts::Customers::CompaniesController < Api::V1::Accounts::Customers::BaseController
  before_action :set_company, except: [:index, :create, :duplicates]

  def index
    scope = JrcCustomers::DirectoryQuery.new(account: Current.account,
                                             filters: params.permit(:q, :relationship_type,
                                                                    :person_kind, :segment, :owner_id,
                                                                    :city, :active, :parent_company_id, :economic_group)).call
    if params[:taxonomy_id].present?
      taxonomy = JrcCustomers::Taxonomy.active.where(account_id: Current.account.id).find(params[:taxonomy_id])
      members = JrcCustomers::SegmentMembers.new(account: Current.account, actor: Current.user, taxonomy: taxonomy)
      scope = scope.where(id: members.companies.reselect(:id))
    end
    records, meta = page_scope(corporate_companies(scope))
    render json: { payload: serializer.companies(records.to_a), meta: meta }
  end

  def show
    branches = corporate_companies.where(parent_company_id: @company.id)
    render json: { payload: serializer.company(@company), branches_total: branches.count,
                   addresses: @company.addresses.where(account_id: Current.account.id).order(:id).as_json,

                   branches: serializer.companies(branches.order(:name, :id).limit(50).to_a) }
  end

  def create
    company = Current.account.master_companies.new
    JrcCustomers::CompanyWriter.new(account: Current.account, actor: Current.user).save!(company: company, attributes: company_params)
    render json: { payload: serializer.company(company) }, status: :created
  end

  def update
    raise ActionController::BadRequest, 'company.revision is required; reload the company' if params.dig(:company, :revision).blank?

    JrcCustomers::CompanyWriter.new(account: Current.account, actor: Current.user).save!(
      company: @company, attributes: company_params, expected_revision: params.dig(:company, :revision)
    )
    render json: { payload: serializer.company(@company) }
  end

  def duplicates
    normalized = JrcCustomers::TaxIdentifier.normalize(params[:tax_id])
    scope = normalized.present? ? corporate_companies.where(tax_id: normalized) : corporate_companies.none
    scope = scope.where.not(id: params[:exclude_id]) if params[:exclude_id].present?
    render json: { payload: serializer.companies(scope.limit(50).to_a), matching: 'exact_normalized_tax_id' }
  end

  def overview
    render json: context(company: @company).overview
  end

  def relationships
    render json: context(company: @company).relationship_map
  end

  def backoffice
    response.headers['Cache-Control'] = 'no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    query = JrcCustomers::BackofficeContext.new(account: Current.account, actor: Current.user, company: @company)
    render json: query.call(params: params.permit(:view, :page, :per_page, :q, :status))
  end

  def timeline
    value = JrcCustomers::Timeline.new(context: context(company: @company), account: Current.account, user: Current.user)
    render json: value.call(cursor: params[:cursor], limit: params.fetch(:per_page, 30))
  end

  def attendance
    response.headers['Cache-Control'] = 'no-store'
    metrics = JrcCustomers::AttendanceMetrics.new(
      account: Current.account, user: Current.user, member: Current.account_user, customer: context(company: @company)
    )
    render json: metrics.call(params.permit(:from, :to, :channel).to_h.symbolize_keys)
  end

  def records
    render_module_records(context(company: @company))
  end

  private

  def set_company
    @company = corporate_companies.find(params[:id])
  end

  def company_params
    params.require(:company).permit(:name, :person_kind, :trade_name, :tax_id, :state_registration, :municipal_registration,
                                   :segment, :size, :website, :domain, :email, :phone_number, :source, :economic_group,
                                   :parent_company_id, :owner_id, :relationship_type, :active, :description,
                                   relationship_tags: [], tags: [], establishment: [:store_code, :cluster, { phones: [] }])
  end
end
