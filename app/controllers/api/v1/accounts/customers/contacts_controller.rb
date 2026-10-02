class Api::V1::Accounts::Customers::ContactsController < Api::V1::Accounts::Customers::BaseController
  before_action :set_contact, only: [:show, :update, :duplicates, :timeline, :merge]

  def index
    scope = Current.account.contacts
    scope = scope.where(company_id: Current.account.master_companies.find(params[:company_id]).id) if params[:company_id].present?
    scope = scope.where(company_id: nil) if params[:unlinked] == 'true'
    if params[:q].present?
      value = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.first(200))}%"
      scope = scope.where('name ILIKE :q OR email ILIKE :q OR phone_number ILIKE :q', q: value)
    end
    records, meta = page_scope(scope.order(:name, :id))
    render json: { payload: serializer.contacts(records.to_a), meta: meta }
  end

  def show
    render json: { payload: serializer.contact(@contact), contact_points: @contact.contact_points.where(account_id: Current.account.id).order(:id).as_json }
  end

  def create
    values = contact_params.to_h
    values['registration_status'] ||= 'registered'
    matches = JrcCustomers::IdentityResolver.new(account: Current.account).call(email: values['email'], phone: values['phone_number'], country: 'BR')
    if matches.exists? && params[:confirm_distinct] != true && params[:confirm_distinct] != 'true'
      return render json: { error: 'Possible duplicate; select existing or confirm a distinct person', code: 'POSSIBLE_DUPLICATE',
                            candidates: serializer.contacts(matches.to_a.first(50)) }, status: :conflict
    end
    values['email'] = JrcCustomers::Identity.email(values['email']) || values['email'] if values['email'].present?
    # Do not discard an invalid supplied telephone: model validation must report it.
    values['phone_number'] = JrcCustomers::Identity.phone(values['phone_number'], country: 'BR') || values['phone_number'] if values['phone_number'].present?
    Contact.transaction do
      contact = Current.account.contacts.create!(values)
      JrcCustomers::Audit.record!(account: Current.account, actor: Current.user, resource: contact,
                                  event_type: 'customer_contact_updated', to_value: serializer.contact(contact))
      render json: { payload: serializer.contact(contact) }, status: :created
    end
  end

  def update
    @contact.with_lock do
      previous = serializer.contact(@contact)
      values = contact_params
      if values.key?(:company_id) && values[:company_id].to_s != @contact.company_id.to_s && @contact.company_id.present? && params[:confirm_reassignment] != true
        raise JrcCustomers::MergePreserver::Conflict, 'Confirm reassignment; the current company and its historical context will change'
      end
      @contact.update!(values)
      JrcCustomers::Audit.record!(account: Current.account, actor: Current.user, resource: @contact,
                                  event_type: values.key?(:company_id) ? 'customer_contact_linked' : 'customer_contact_updated',
                                  from_value: previous, to_value: serializer.contact(@contact))
    end
    render json: { payload: serializer.contact(@contact) }
  end

  def duplicates
    records = JrcCustomers::IdentityResolver.new(account: Current.account).call(email: @contact.email, phone: @contact.phone_number, exclude_id: @contact.id).to_a
    @contact.contact_points.where(account_id: Current.account.id).limit(50).each do |point|
      inputs = if JrcCustomers::Identity::EMAIL_KINDS.include?(point.kind)
                 { email: point.normalized_value }
               elsif JrcCustomers::Identity::PHONE_KINDS.include?(point.kind)
                 { phone: point.normalized_value }
               else
                 { extension: point.normalized_value }
               end
      records += JrcCustomers::IdentityResolver.new(account: Current.account).call(**inputs, exclude_id: @contact.id).to_a
    end
    records.uniq!(&:id)
    render json: { payload: serializer.contacts(records.first(50)), truncated: records.size > 50, destructive_auto_merge: false }
  end

  def merge
    authorize_admin!
    raise ActionController::BadRequest, 'Explicit confirmation required' unless params[:confirm] == true

    source = Current.account.contacts.find(params.require(:source_contact_id))
    ContactMergeAction.new(account: Current.account, base_contact: @contact, mergee_contact: source).perform
    render json: { payload: serializer.contact(@contact.reload) }
  end

  def timeline
    value = JrcCustomers::Timeline.new(context: context(contact: @contact), account: Current.account, user: Current.user)
    render json: value.call(cursor: params[:cursor], limit: params.fetch(:per_page, 30))
  end

  private

  def set_contact
    @contact = Current.account.contacts.find(params[:id])
  end

  def contact_params
    params.require(:contact).permit(:name, :email, :phone_number, :company_id, :job_title, :department, :registration_status)
  end
end
