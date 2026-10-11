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

  # Account-wide candidates, using the same identities as per-contact review.
  # UNION removes repeated identities on one person before counting people.
  def duplicates
    emails = @account.contacts.where.not(email: [nil, '']).select("id AS contact_id, 'email' AS kind, lower(trim(email)) AS value")
    phones = @account.contacts.where.not(phone_number: [nil, ''])
                     .select("id AS contact_id, 'phone' AS kind, regexp_replace(phone_number, '[^0-9]', '', 'g') AS value")
    points = JrcCustomers::ContactPoint.where(account_id: @account.id)
               .select("contact_id, CASE WHEN kind IN ('email', 'corporate_email', 'alternate_email') THEN 'email' " \
                       "WHEN kind = 'extension' THEN 'extension' ELSE 'phone' END AS kind, " \
                       "CASE WHEN kind IN ('phone', 'mobile', 'whatsapp', 'whatsapp_business') " \
                       "THEN regexp_replace(normalized_value, '[^0-9]', '', 'g') ELSE normalized_value END AS value")
    identities = "#{emails.to_sql} UNION #{phones.to_sql} UNION #{points.to_sql}"
    matches = "SELECT contact_id FROM (SELECT contact_id, COUNT(*) OVER (PARTITION BY kind, value) AS people " \
              "FROM (#{identities}) AS identities WHERE value IS NOT NULL AND value <> '') AS matches WHERE people > 1"
    @account.contacts.where("contacts.id IN (#{matches})")
  end

  private

  def point_contacts(kinds, value)
    ids = JrcCustomers::ContactPoint.where(account_id: @account.id, kind: kinds, normalized_value: value).select(:contact_id)
    @account.contacts.where(id: ids)
  end
end
