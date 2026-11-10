class Api::V1::Accounts::Customers::ImportRunsController < Api::V1::Accounts::Customers::BaseController
  before_action :private_response
  rescue_from JrcCustomers::ImportFile::InvalidFile, JrcCustomers::CompanyImport::InvalidImport do |exception|
    render json: { error: exception.message, code: 'INVALID_IMPORT' }, status: :unprocessable_entity
  end

  def metadata
    kinds = access.available_kinds
    render json: { available_kinds: kinds, fields: kinds.index_with { |kind| runs.fields_for(kind) },
                   max_bytes: JrcCustomers::CompanyImport::MAX_BYTES, max_rows: JrcCustomers::CompanyImport::MAX_ROWS,
                   delimiters: JrcCustomers::ImportFile::DELIMITERS }
  end

  def template
    kind = params.require(:kind)
    access.authorize!(kind: kind)
    headers = template_fields(kind)
    send_data "\uFEFF#{CSV.generate_line(headers, col_sep: ';')}",
              type: 'text/csv; charset=utf-8', disposition: 'attachment', filename: "jrc-#{kind}-modelo.csv"
  end

  def index
    records, meta = page_scope(filtered_history.order(created_at: :desc, id: :desc))
    render json: { payload: records.map { |record| presenter.summary(record) }, meta: meta }
  end

  def show
    render json: presenter.detail(runs.find(params[:id]))
  end

  def create
    file = params.require(:file)
    raise ActionController::BadRequest, 'Upload a UTF-8 CSV file' unless file.respond_to?(:read) && file.respond_to?(:size)
    raise ActionController::BadRequest, 'File exceeds 1 MiB' if file.size > JrcCustomers::CompanyImport::MAX_BYTES

    record = runs.create!(kind: params.require(:kind), filename: file.original_filename, delimiter: params[:delimiter].presence,
                          content: file.read(JrcCustomers::CompanyImport::MAX_BYTES + 1))
    render json: presenter.detail(record), status: :created
  end

  def preview
    mapping = hash_parameter(:column_mapping).permit!.to_h
    options = hash_parameter(:import_options).permit(:existing, confirmations: %i[reassignment primary_change]).to_h
    options.fetch('existing') { raise ActionController::BadRequest, 'Choose how to handle existing records' }
    result = review.preview!(id: params[:id], mapping: mapping, options: options)
    render json: { payload: presenter.summary(result.fetch(:run)), rows: result.fetch(:plan).public_rows,
                   errors: result.fetch(:plan).errors, token: result.fetch(:token), expires_in_seconds: 900 }
  end

  def apply
    execution = JrcCustomers::ImportExecution.new(account: Current.account, actor: Current.user)
    record = execution.apply!(id: params[:id], token: params.require(:token), confirmed: params[:confirm])
    render json: { payload: presenter.summary(record) }
  end

  def rows
    records, meta = page_scope(results.rows(runs.find(params[:id])))
    render json: { payload: results.serialize_rows(records.to_a), meta: meta }
  end

  def errors
    run = runs.find(params[:id])
    if request.format.csv?
      send_data results.error_csv(run), type: 'text/csv; charset=utf-8', disposition: 'attachment', filename: "jrc-import-#{run.id}-erros.csv"
    else
      records, meta = page_scope(results.errors(run))
      render json: { payload: results.serialize_errors(records.to_a), meta: meta }
    end
  end

  private

  def filtered_history
    scope = runs.scope
    filters = params.permit(:kind, :status, :q)
    scope = scope.where("source_metadata ->> 'kind' = ?", filters[:kind]) if filters[:kind].present?
    if filters[:status].present?
      raise ActionController::BadRequest, 'Unsupported import status' unless DataImport.statuses.key?(filters[:status])

      scope = scope.where(status: filters[:status])
    end
    scope = scope.where('name ILIKE ?', "%#{DataImport.sanitize_sql_like(filters[:q].to_s.first(100))}%") if filters[:q].present?
    scope
  end

  def private_response
    response.headers['Cache-Control'] = 'no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
  end

  def access
    JrcCustomers::ImportAccess.new(account: Current.account, actor: Current.user)
  end

  def runs
    JrcCustomers::ImportRuns.new(account: Current.account, actor: Current.user)
  end

  def review
    JrcCustomers::ImportReview.new(account: Current.account, actor: Current.user)
  end

  def presenter
    JrcCustomers::ImportPresenter.new(account: Current.account, actor: Current.user)
  end

  def results
    JrcCustomers::ImportResults.new(account: Current.account, actor: Current.user)
  end

  def hash_parameter(key)
    value = params.require(key)
    raise ActionController::BadRequest, 'Expected an object' unless value.is_a?(ActionController::Parameters)

    value
  end

  def template_fields(kind)
    return %w[name person_kind tax_id trade_name relationship_type] if kind == 'companies'
    return %w[name email phone_number identifier company_id job_title department] if kind == 'contacts'

    %w[company.name company.person_kind company.tax_id contact.name contact.email contact.phone_number contact.company_role]
  end
end
