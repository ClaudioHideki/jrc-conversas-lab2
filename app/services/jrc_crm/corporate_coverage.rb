# Organizational coverage is independent of native roles and functional permissions.
class JrcCrm::CorporateCoverage
  SOURCE_LINKS = { 'sales_order_id' => :jrc_crm_sales_orders, 'deal_id' => :jrc_crm_deals,
                   'invoice_id' => :jrc_crm_invoices, 'contract_id' => :jrc_crm_contracts }.freeze
  def self.for_actor(account, user, relation)
    user ? new(account: account, user: user).restrict(relation) : relation
  end

  def self.goal_team_members(goal)
    team_ids = goal.account.teams.where(id: goal.team_id).select(:id)
    ::TeamMember.where(team_id: team_ids).select(:user_id)
  end

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  def group?
    scopes.exists?(scope: 'GROUP')
  end

  def company_ids
    companies = @account.master_companies.where(relationship_type: 'internal')
    return companies.select(:id) if group?

    direct = scopes.where(scope: 'COMPANY').select(:company_id)
    units = @account.jrc_crm_business_units.where(id: scopes.where(scope: 'BUSINESS_UNIT').select(:business_unit_id)).select(:company_id)
    companies.where(id: direct).or(companies.where(id: units)).select(:id)
  end

  def unit_ids
    units = @account.jrc_crm_business_units.where.not(company_id: nil)
    return units.select(:id) if group?

    company_scopes = scopes.where(scope: 'COMPANY').select(:company_id)
    units.where(company_id: company_scopes).or(units.where(id: scopes.where(scope: 'BUSINESS_UNIT').select(:business_unit_id))).select(:id)
  end

  def company_allowed?(id)
    @account.master_companies.where(id: company_ids).exists?(id: id)
  end

  def unit_allowed?(id)
    @account.jrc_crm_business_units.where(id: unit_ids).exists?(id: id)
  end

  def companies(relation)
    relation = account_scope(relation)
    relation.where.not(relationship_type: 'internal').or(relation.where(id: company_ids))
  end

  def configured?
    @account.jrc_crm_business_units.where.not(company_id: nil).exists?
  end

  def restrict(relation)
    relation = account_scope(relation)
    return companies(relation) if relation.klass.table_name == 'companies'
    return relation unless configured?
    return relation if group?
    return relation.where(id: unit_ids) if relation.klass == JrcCrm::BusinessUnit

    result = restrict_links(relation)
    result = restrict_operating_company(result)
    result = restrict_units(result) if relation.klass.column_names.include?('business_unit_id')
    relation.klass == JrcCrm::Deal ? restrict_deal_metadata(result) : result
  end

  def service_desk_units(relation)
    return relation unless configured?
    return relation if group?

    linked = @account.jrc_crm_business_units.where("settings ? 'service_desk_unit_id'")
    permitted = linked.where(id: unit_ids).pluck(Arel.sql("settings ->> 'service_desk_unit_id'"))
    relation.where(id: permitted)
  end

  private

  def account_scope(relation)
    return relation if relation.where_values_hash['account_id'] == @account.id

    relation.where(account_id: @account.id)
  end

  def restrict_links(relation)
    SOURCE_LINKS.each do |column, association|
      next unless relation.klass.column_names.include?(column)

      allowed = restrict(@account.public_send(association)).select(:id)
      relation = relation.where(column => nil).or(relation.where(column => allowed))
    end
    relation
  end

  def restrict_units(relation)
    table = relation.klass.arel_table
    condition = table[:business_unit_id].in(unit_ids.arel)
    fallback = inherited_unit(relation)
    condition = condition.or(table[:business_unit_id].eq(nil).and(fallback)) if fallback
    relation.where(condition)
  end

  def restrict_operating_company(relation)
    return relation unless relation.klass.column_names.include?('operating_company_id')

    relation.where(operating_company_id: nil).or(relation.where(operating_company_id: company_ids))
  end

  def inherited_unit(relation)
    direct = direct_unit_reference(relation)
    return direct if direct

    sources = SOURCE_LINKS.filter_map do |column, association|
      next unless relation.klass.column_names.include?(column)

      source = restrict(@account.public_send(association)).select(:id)
      relation.klass.arel_table[column].in(source.arel)
    end
    sources.reduce { |condition, extra| condition.or(extra) }
  end

  def direct_unit_reference(relation)
    table = relation.klass.arel_table
    return Arel.sql('TRUE') if relation.klass == JrcCrm::Product
    return table[:operating_company_id].in(scopes.where(scope: 'COMPANY').select(:company_id).arel) if relation.klass == JrcOperations::Queue
    return unless relation.klass == JrcCrm::Deal

    Arel.sql("#{table.name}.metadata ->> 'business_unit_id'").in(unit_ids.reselect(Arel.sql('id::text')).arel)
  end

  def restrict_deal_metadata(relation)
    table = relation.klass.arel_table
    reference = Arel.sql("#{table.name}.metadata ->> 'business_unit_id'")
    permitted = @account.jrc_crm_business_units.where(company_id: nil).or(@account.jrc_crm_business_units.where(id: unit_ids))
    relation.where(reference.eq(nil).or(reference.eq('')).or(reference.in(permitted.select(Arel.sql('id::text')).arel)))
  end

  def scopes
    @account.jrc_crm_user_business_units.structure_managed.active.where(user_id: @user&.id)
  end
end
