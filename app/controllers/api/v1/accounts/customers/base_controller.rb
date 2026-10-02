class Api::V1::Accounts::Customers::BaseController < Api::V1::Accounts::BaseController
  before_action :authorize_directory!
  rescue_from ActiveRecord::RecordInvalid, with: :invalid_record
  rescue_from ActiveRecord::RecordNotUnique, with: :duplicate_record
  rescue_from ActiveRecord::InvalidForeignKey, with: :invalid_reference
  rescue_from JrcCustomers::MergePreserver::Conflict, JrcCustomers::LegacyCompanyMapper::Conflict,
              JrcCustomers::LeadContactLinker::Conflict, JrcCustomers::CompanyWriter::StaleRevision, with: :conflict
  rescue_from JrcCustomers::Timeline::InvalidCursor, with: :bad_cursor

  private

  def authorize_directory!
    authorize :directory, :access?, policy_class: JrcCustomers::DirectoryPolicy
  end

  def authorize_admin!
    authorize :directory, :administer?, policy_class: JrcCustomers::DirectoryPolicy
  end

  def serializer
    @serializer ||= JrcCustomers::Serializer.new(account: Current.account)
  end

  def page_scope(relation)
    page = params.fetch(:page, 1).to_i.clamp(1, 10_000)
    size = params.fetch(:per_page, 25).to_i.clamp(1, 50)
    [relation.limit(size).offset((page - 1) * size), { page: page, per_page: size, total: relation.unscope(:order).count }]
  end

  def invalid_record(exception)
    render json: { error: 'Validation failed', details: exception.record.errors.to_hash }, status: :unprocessable_entity
  end

  def duplicate_record(_exception)
    render json: { error: 'Duplicate identifier in this account. Refresh and select the existing record.', code: 'DUPLICATE' }, status: :conflict
  end

  def invalid_reference(_exception)
    render json: { error: 'Invalid or cross-account reference', code: 'INVALID_REFERENCE' }, status: :unprocessable_entity
  end

  def conflict(exception)
    render json: { error: exception.message, code: 'REVIEW_REQUIRED' }, status: :conflict
  end

  def bad_cursor(exception)
    render json: { error: exception.message }, status: :bad_request
  end

  def context(company: nil, contact: nil)
    JrcCustomers::Customer360.new(account: Current.account, user: Current.user, account_user: Current.account_user,
                                  company: company, contact: contact)
  end
end
