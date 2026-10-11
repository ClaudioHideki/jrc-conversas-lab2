class JrcCustomers::ContactQuery
  def initialize(account:, scope:, query:, view: nil)
    @account, @scope, @term = account, scope, query.to_s.strip.first(200)
    @scope = directory_scope(view)
  end

  def call
    return @scope if @term.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@term)}%"
    matched = @scope.where('contacts.name ILIKE :q OR contacts.email ILIKE :q OR contacts.phone_number ILIKE :q OR contacts.identifier ILIKE :q', q: pattern)
    companies = JrcCustomers::DirectoryQuery.new(account: @account, filters: { q: @term }).call.select(:id)
    points = JrcCustomers::ContactPoint.where(account_id: @account.id).where('value ILIKE ?', pattern).select(:contact_id)
    matched = matched.or(@scope.where(company_id: companies)).or(@scope.where(id: points))
    digits = @term.gsub(/\D/, '')
    if @term.match?(/\A[+0-9().\s\/-]+\z/) && digits.length >= 4
      matched = matched.or(@scope.where("regexp_replace(COALESCE(contacts.phone_number, ''), '[^0-9]', '', 'g') LIKE :q OR regexp_replace(COALESCE(contacts.identifier, ''), '[^0-9]', '', 'g') LIKE :q", q: "%#{digits}%"))
    end
    matched
  end

  private

  def directory_scope(view)
    case view
    when nil, '', 'people'
      @scope
    when 'unassigned'
      companies = @account.master_companies.where(owner_id: nil).select(:id)
      @scope.where(company_id: nil).or(@scope.where(company_id: companies))
    when 'duplicates'
      @scope.where(id: JrcCustomers::IdentityResolver.new(account: @account).duplicates.select(:id))
    else
      raise ActionController::BadRequest, 'Invalid contact directory view'
    end
  end
end
