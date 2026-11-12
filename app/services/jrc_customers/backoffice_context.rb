# A company view of the native operational workspace, never a second queue or
# document/approval engine. Source ownership and issuer/unit coverage still apply.
class JrcCustomers::BackofficeContext
  VIEWS = { 'requests' => nil, 'documents' => 'docs', 'approvals' => 'approvals', 'contracts' => 'contracts',
            'issues' => 'issues', 'history' => nil }.freeze

  def initialize(account:, actor:, company:)
    @account = account
    @actor = actor
    @company = company
    @access = JrcBackoffice::ContractAccess.new(account: account, actor: actor)
  end

  def call(params: {})
    filters = params.to_h.with_indifferent_access
    view = filters.fetch(:view, 'requests')
    raise ActionController::BadRequest, 'Invalid Backoffice context view' unless VIEWS.key?(view)

    rows = scope
    result = if view == 'history'
               history(rows, filters)
             else
               workspace(rows, filters, view)
             end
    authorize_company!
    ids = view == 'history' ? result[:data].pluck(:request_id) : result[:data].pluck(:id)
    raise Pundit::NotAuthorizedError unless (ids - scope.where(id: ids).pluck(:id)).empty?

    result.merge(company_id: @company.id, view: view)
  end

  private

  def workspace(rows, filters, view)
    JrcCrm::BackofficeWorkspace.new(scope: rows, user: @actor, account: @account,
                                    params: filters.slice(:page, :per_page, :q, :status).merge(view: VIEWS.fetch(view))).call
  end

  def authorize_company!
    @access.membership!
    JrcCustomers::ContactDirectory.new(account: @account, actor: @actor).authorize!
    companies = JrcCrm::CorporateCoverage.new(account: @account, user: @actor).companies(@account.master_companies)
    raise ActiveRecord::RecordNotFound unless @company.account_id == @account.id && companies.exists?(id: @company.id)
  end

  def scope
    authorize_company!
    # The native workspace resolves its customer through request.contact. Do
    # not infer/rebind unidentified legacy requests from arbitrary parameters.
    contacts = @account.contacts.where(company_id: @company.id).select(:id)
    @access.requests.where(contact_id: contacts)
  end

  def history(rows, filters)
    events = JrcCrm::AuditEvent.where(account_id: @account.id, resource_type: 'JrcCrm::BackofficeRequest', resource_id: rows.select(:id))
    total = events.count
    size = filters.fetch(:per_page, 20).to_i.clamp(1, 50)
    pages = [(total / size.to_f).ceil, 1].max
    page = filters.fetch(:page, 1).to_i.clamp(1, pages)
    selected = events.order(created_at: :desc, id: :desc).offset((page - 1) * size).limit(size)
    { data: selected.map { |event| { id: event.id, request_id: event.resource_id, event_type: event.event_type, created_at: event.created_at } },
      meta: { total: total, page: page, per_page: size, pages: pages } }
  end
end
