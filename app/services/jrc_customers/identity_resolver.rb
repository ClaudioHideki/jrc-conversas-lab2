class JrcCustomers::IdentityResolver
  def initialize(account:)
    @account = account
  end

  # A shared telephone/email may belong to more than one person. Return all
  # candidates (bounded), not the first arbitrary result. Never performs merge.
  def call(email: nil, phone: nil, extension: nil, exclude_id: nil, country: nil)
    normalized_email = JrcCustomers::Identity.email(email)
    normalized_phone = JrcCustomers::Identity.phone(phone, country: country)
    normalized_extension = JrcCustomers::Identity.point('extension', extension)
    scope = @account.contacts.none
    if normalized_email
      scope = scope.or(@account.contacts.where('lower(trim(email)) = ?', normalized_email))
      scope = scope.or(point_contacts(JrcCustomers::Identity::EMAIL_KINDS, normalized_email))
    end
    if normalized_phone
      scope = scope.or(@account.contacts.where("regexp_replace(phone_number, '[^0-9]', '', 'g') = ?", normalized_phone.delete_prefix('+')))
      scope = scope.or(point_contacts(JrcCustomers::Identity::PHONE_KINDS, normalized_phone))
    end
    scope = scope.or(point_contacts(['extension'], normalized_extension)) if normalized_extension
    scope = scope.where.not(id: exclude_id) if exclude_id.present?
    scope.distinct.order(:id).limit(51)
  end

  private

  def point_contacts(kinds, value)
    ids = JrcCustomers::ContactPoint.where(account_id: @account.id, kind: kinds, normalized_value: value).select(:contact_id)
    @account.contacts.where(id: ids)
  end
end
