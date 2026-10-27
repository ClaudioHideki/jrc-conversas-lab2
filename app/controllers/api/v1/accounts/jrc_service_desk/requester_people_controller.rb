# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::RequesterPeopleController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  before_action :capture_requester_context
  rescue_from ::JrcCustomers::RequesterWriter::Duplicate, with: :possible_duplicate
  rescue_from ::JrcCustomers::RequesterWriter::ReviewRequired, with: :review_required

  def index
    prepare_directory!
    scope = ::JrcCustomers::ContactQuery.new(account: @context.account, scope: @directory.visible_contacts, query: @filters['q'], include_company: false).call
    render json: base_payload.merge(items: paginated_people(scope),
                                    meta: { total: scope.count, page: @filters.page, per_page: @filters.per_page }, can_create: may_create?,
                                    company: @company && { id: @company.id, name: @company.name })
  end

  def show
    prepare_directory!
    contact = @directory.visible_contacts.find(::JrcServiceDesk::Input.id(params[:id]))
    @directory.validate!(contact, company_id: @company&.id)
    render json: base_payload.merge(person: person(contact))
  end

  def create
    authorize :lookup, :index?, policy_class: ::JrcServiceDesk::LookupPolicy
    values = body_values(%w[unit_id company_id contact request_key confirm_distinct])
    attributes = ::JrcServiceDesk::Input.attributes(values.fetch('contact'), %w[name email phone_number])
    contact = ::JrcServiceDesk::RequesterService.new(user_context: @context.to_h).create(
      unit_id: values.fetch('unit_id'), company_id: values.fetch('company_id'), attributes: attributes, request_key: values.fetch('request_key'),
      confirm_distinct: values.fetch('confirm_distinct', false)
    )
    render json: base_payload.merge(person: person(contact)), status: :created
  end

  def link
    authorize :lookup, :index?, policy_class: ::JrcServiceDesk::LookupPolicy
    values = body_values(%w[unit_id company_id confirm])
    contact = ::JrcServiceDesk::RequesterService.new(user_context: @context.to_h).link(
      unit_id: values.fetch('unit_id'), company_id: values.fetch('company_id'), contact_id: params[:id], confirm: values['confirm']
    )
    render json: base_payload.merge(person: person(contact))
  end

  private

  # Native around-handlers clear Current while unwinding an exception. Keep the
  # already authenticated context for safe duplicate projections in rescue_from.
  def capture_requester_context
    @context = ::JrcServiceDesk::OperationalContext.new(pundit_user)
  end

  def base_payload
    { contract_version: 1, account_id: @context.account.id.to_s }
  end

  def prepare_directory!
    authorize :lookup, :index?, policy_class: ::JrcServiceDesk::LookupPolicy
    @filters = ::JrcServiceDesk::QueryParameters.new(query_values, catalog: true)
    raise Pundit::NotAuthorizedError unless @context.capability?(:customers_view)

    authorize :directory, :access?, policy_class: ::JrcCustomers::DirectoryPolicy
    policy_scope(::JrcServiceDesk::Unit).find(@filters['unit_id'])
    @directory = ::JrcServiceDesk::RequesterDirectory.new(@context)
    @company = @directory.company!(@filters['company_id']) if @filters['company_id']
  end

  def paginated_people(scope)
    # ContactPolicy#show? permits every contact (including its Enterprise overlay).
    # Visibility is enforced by the directory relation; keep each returned person's authorization below.
    records = scope.order(:name, :id).offset(@filters.offset).limit(@filters.per_page).to_a
    rows = ::JrcCustomers::Serializer.new(account: @context.account).contacts(records)
    records.zip(rows).map { |record, row| person(record, row) }
  end

  def person(record, row = nil)
    context = @context
    Pundit.authorize(context.to_h, record, :show?)
    reason = ::JrcCustomers::RequesterIdentity.reason(record)
    row ||= ::JrcCustomers::Serializer.new(account: context.account).contact(record)
    row.merge('requester_eligible' => reason.nil?, 'review_reason' => reason,
              'can_link' => reason.nil? && context.capability?(:tickets_create) &&
                ::JrcCustomers::DirectoryPolicy.new(context.to_h, :directory).access? &&
                Pundit.policy!(context.to_h, record).update?)
  end

  def may_create?
    @context.capability?(:tickets_create) && Pundit.policy!(@context.to_h, Contact).create?
  end

  def possible_duplicate(error)
    context = ::JrcServiceDesk::OperationalContext.new(@context.to_h)
    @context = context
    unless context.native_operator? && context.capability?(:customers_view) && context.capability?(:tickets_create) &&
           ::JrcCustomers::DirectoryPolicy.new(context.to_h, :directory).access?
      return render_unauthorized(nil)
    end
    visible = ::JrcServiceDesk::RequesterDirectory.new(context).visible_contacts.where(id: error.records.map(&:id))
    records = visible.select { |record| Pundit.policy!(context.to_h, record).show? }
    render json: { code: 'POSSIBLE_DUPLICATE', allow_distinct: error.allow_distinct,
                   candidates: records.first(50).map { |record| person(record) } }, status: :conflict
  end

  def review_required(_error)
    render json: { code: 'REQUESTER_REVIEW_REQUIRED' }, status: :conflict
  end
end
