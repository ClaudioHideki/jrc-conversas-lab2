class JrcCustomers::DirectoryQuery
  def initialize(account:, filters: {})
    @account, @filters = account, filters.to_h.with_indifferent_access
  end

  def call
    scope = @account.master_companies
    %w[relationship_type person_kind segment owner_id parent_company_id economic_group].each do |key|
      scope = scope.where(key => @filters[key]) if @filters[key].present?
    end
    scope = scope.where(active: ActiveModel::Type::Boolean.new.cast(@filters[:active])) if @filters[:active].present?
    if @filters[:city].present?
      ids = JrcCustomers::Address.where(account_id: @account.id).where('city ILIKE ?', pattern(@filters[:city])).select(:company_id)
      scope = scope.where(id: ids)
    end
    term = @filters[:q].to_s.strip.first(200)
    return scope.order(:name, :id) if term.blank?

    contacts = @account.contacts.where('name ILIKE :q OR email ILIKE :q OR phone_number ILIKE :q', q: pattern(term))
    point_ids = JrcCustomers::ContactPoint.where(account_id: @account.id).where('value ILIKE ?', pattern(term)).select(:contact_id)
    contacts = contacts.or(@account.contacts.where(id: point_ids))
    digits = term.gsub(/[^0-9]/, '')
    numeric_query = term.match?(/\A[+0-9().\s-]+\z/) && digits.length >= 4
    if numeric_query
      contacts = contacts.or(@account.contacts.where("regexp_replace(phone_number, '[^0-9]', '', 'g') LIKE ?", "%#{digits}%"))
      numeric_points = JrcCustomers::ContactPoint.where(account_id: @account.id, kind: JrcCustomers::Identity::PHONE_KINDS + ['extension'])
                                               .where('normalized_value LIKE ?', "%#{digits}%").select(:contact_id)
      contacts = contacts.or(@account.contacts.where(id: numeric_points))
    end
    matched = scope.where('name ILIKE :q OR trade_name ILIKE :q OR domain ILIKE :q OR phone_number ILIKE :q OR email ILIKE :q', q: pattern(term))
    matched = matched.or(scope.where("regexp_replace(phone_number, '[^0-9]', '', 'g') LIKE ?", "%#{digits}%")) if numeric_query
    normalized = JrcCustomers::TaxIdentifier.normalize(term)
    matched = matched.or(scope.where('tax_id LIKE ?', "#{ActiveRecord::Base.sanitize_sql_like(normalized)}%")) if normalized.present? && normalized.match?(/\A[A-Z0-9]+\z/)
    matched.or(scope.where(id: contacts.where.not(company_id: nil).select(:company_id))).order(:name, :id)
  end

  private

  def pattern(value)
    "%#{ActiveRecord::Base.sanitize_sql_like(value.to_s)}%"
  end
end
