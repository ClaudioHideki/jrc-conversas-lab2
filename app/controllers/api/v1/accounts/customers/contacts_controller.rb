class Api::V1::Accounts::Customers::ContactsController < Api::V1::Accounts::Customers::BaseController
  before_action :set_contact, only: %i[show update duplicates overview timeline records company_history merge]

  def index
    scope = contact_directory.scope
    if params[:taxonomy_id].present?
      taxonomy = JrcCustomers::Taxonomy.active.where(account_id: Current.account.id).find(params[:taxonomy_id])
      members = JrcCustomers::SegmentMembers.new(account: Current.account, actor: Current.user, taxonomy: taxonomy)
      scope = scope.where(id: members.contacts.reselect(:id))
    end
    scope = scope.where(company_id: corporate_companies.find(params[:company_id]).id) if params[:company_id].present?
    scope = scope.where(company_id: nil) if params[:unlinked] == 'true'
    scope = JrcCustomers::ContactQuery.new(account: Current.account, scope: scope, query: params[:q]).call
    records, meta = page_scope(scope.order(:name, :id))
    render json: { payload: serializer.contacts(records.to_a), meta: meta }
  end

  def show
    render json: { payload: serializer.contact(@contact), contact_points: @contact.contact_points.where(account_id: Current.account.id).order(:id).as_json }
  end

  def overview
    render json: context(contact: @contact).overview
  end

  def records
    render_module_records(context(contact: @contact))
  end

  def company_history
    history = JrcCustomers::CompanyContactHistory.new(account: Current.account, actor: Current.user, contact: @contact)
    rows, meta = page_scope(history.scope.order(created_at: :desc, id: :desc))
    response.headers['Cache-Control'] = 'no-store'
    render json: { payload: history.serialize(rows.to_a), meta: meta }
  end

  def create
    values = contact_params.to_h
    personal_identifier = values.delete('personal_tax_identifier')
    values['registration_status'] ||= 'registered'
    resolver = JrcCustomers::IdentityResolver.new(account: Current.account, personal_tax_identifier: personal_identifier)
    matches = resolver.call(email: values['email'], phone: values['phone_number'], country: 'BR').merge(contact_directory.scope)
    if matches.exists? && params[:confirm_distinct] != true && params[:confirm_distinct] != 'true'
      return render json: { error: 'Possible duplicate; select existing or confirm a distinct person', code: 'POSSIBLE_DUPLICATE',
                            candidates: serializer.contacts(matches.to_a.first(50)) }, status: :conflict
    end
    values['email'] = JrcCustomers::Identity.email(values['email']) || values['email'] if values['email'].present?
    # Do not discard an invalid supplied telephone: model validation must report it.
    values['phone_number'] = JrcCustomers::Identity.phone(values['phone_number'], country: 'BR') || values['phone_number'] if values['phone_number'].present?
    Contact.transaction do
      Current.account.lock! if personal_identifier.present?
      contact = Current.account.contacts.create!(values)
      if personal_identifier.present?
        JrcCustomers::SigningIdentityWriter.new(account: Current.account, actor: Current.user)
                                          .save!(contact_id: contact.id, personal_tax_identifier: personal_identifier, expected_revision: 0)
      end
      JrcCustomers::Audit.record!(account: Current.account, actor: Current.user, resource: contact,
                                  event_type: 'customer_contact_updated', to_value: serializer.contact(contact))
      render json: { payload: serializer.contact(contact) }, status: :created
    end
  end

  def update
    writer = JrcCustomers::CompanyContactWriter.new(account: Current.account, actor: Current.user)
    @contact = writer.update!(id: @contact.id, attributes: contact_params,
                              confirm_reassignment: params[:confirm_reassignment] == true,
                              confirm_primary_change: params[:confirm_primary_change] == true)
    render json: { payload: serializer.contact(@contact) }
  end

  def duplicates
    directory_scope = contact_directory.scope
    records = JrcCustomers::IdentityResolver.new(account: Current.account)
                                          .call(email: @contact.email, phone: @contact.phone_number, exclude_id: @contact.id).merge(directory_scope).to_a
    @contact.contact_points.where(account_id: Current.account.id).limit(50).each do |point|
      inputs = if JrcCustomers::Identity::EMAIL_KINDS.include?(point.kind)
                 { email: point.normalized_value }
               elsif JrcCustomers::Identity::PHONE_KINDS.include?(point.kind)
                 { phone: point.normalized_value }
               else
                 { extension: point.normalized_value }
               end
      records += JrcCustomers::IdentityResolver.new(account: Current.account).call(**inputs, exclude_id: @contact.id).merge(directory_scope).to_a
    end
    records.uniq!(&:id)
    render json: { payload: serializer.contacts(records.first(50)), truncated: records.size > 50, destructive_auto_merge: false }
  end

  def merge
    authorize_admin!
    raise ActionController::BadRequest, 'Explicit confirmation required' unless params[:confirm] == true

    source = contact_directory.find(params.require(:source_contact_id))
    ContactMergeAction.new(account: Current.account, base_contact: @contact, mergee_contact: source).perform
    render json: { payload: serializer.contact(@contact.reload) }
  end

  def timeline
    value = JrcCustomers::Timeline.new(context: context(contact: @contact), account: Current.account, user: Current.user)
    render json: value.call(cursor: params[:cursor], limit: params.fetch(:per_page, 30))
  end

  private

  def set_contact
    @contact = contact_directory.find(params[:id])
  end

  def contact_directory
    JrcCustomers::ContactDirectory.new(account: Current.account, actor: Current.user)
  end

  def contact_params
    fields = [:name, :email, :phone_number, :company_id, :job_title, :department, :registration_status]
    fields << :personal_tax_identifier if action_name == 'create'
    fields += %i[company_role company_primary company_contact_status] if action_name == 'update'
    values = params.require(:contact).permit(*fields)
    company = Current.account.master_companies.find_by(id: values[:company_id])
    corporate_companies.find(company.id) if company
    values
  end
end
