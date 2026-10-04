class Api::V1::Accounts::Customers::CompaniesController < Api::V1::Accounts::Customers::BaseController
  before_action :set_company, except: [:index, :create, :duplicates]

  def index
    records, meta = page_scope(JrcCustomers::DirectoryQuery.new(account: Current.account, filters: params.permit(:q, :relationship_type, :person_kind, :segment, :owner_id, :city, :active, :parent_company_id, :economic_group)).call)
    render json: { payload: serializer.companies(records.to_a), meta: meta }
  end

  def show
    render json: { payload: serializer.company(@company), branches_total: Current.account.master_companies.where(parent_company_id: @company.id).count, addresses: @company.addresses.where(account_id: Current.account.id).order(:id).as_json,
                   branches: serializer.companies(Current.account.master_companies.where(parent_company_id: @company.id).order(:name, :id).limit(50).to_a) }
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
    scope = normalized.present? ? Current.account.master_companies.where(tax_id: normalized) : Current.account.master_companies.none
    scope = scope.where.not(id: params[:exclude_id]) if params[:exclude_id].present?
    render json: { payload: serializer.companies(scope.limit(50).to_a), matching: 'exact_normalized_tax_id' }
  end

  def overview
    render json: context(company: @company).overview
  end

  def timeline
    value = JrcCustomers::Timeline.new(context: context(company: @company), account: Current.account, user: Current.user)
    render json: value.call(cursor: params[:cursor], limit: params.fetch(:per_page, 30))
  end

  def records
    relation = context(company: @company).sources[params[:kind].to_s]
    raise ActionController::BadRequest, 'Unsupported or unavailable module' unless relation

    records, meta = page_scope(relation.order(created_at: :desc, id: :desc))
    # Explicit safe fields: never return tokens, transcripts, private messages, configuration or audit snapshots.
    fields = %w[id display_id title name status created_at updated_at contact_id company_id deal_id lead_id
                requester_id unit_id status_id priority_id project_id key due_on starts_on contract_number order_number
                due_at completed_at direction duration_seconds provider started_at campaign_id sent_at value_cents total_cents proposal_number]
    payload = records.map do |record|
      row = record.attributes.slice(*fields)
      if record.is_a?(JrcServiceDesk::Ticket)
        row['status'] = record.status.name
        row['phase'] = record.status.phase
      end
      row
    end
    render json: { payload: payload, meta: meta }
  end

  private

  def set_company
    @company = Current.account.master_companies.find(params[:id])
  end

  def company_params
    params.require(:company).permit(:name, :person_kind, :trade_name, :tax_id, :state_registration, :municipal_registration,
                                   :segment, :size, :website, :domain, :email, :phone_number, :source, :economic_group,
                                   :parent_company_id, :owner_id, :relationship_type, :active, :description,
                                   relationship_tags: [], tags: [])
  end
end
