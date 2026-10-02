class JrcCustomers::LegacyCompanyMapper
  class Conflict < StandardError; end

  def initialize(account:, organization:, target_company_id: nil)
    @account = account
    @organization = organization
    @target_company_id = target_company_id.presence&.to_i
    raise Conflict, 'Organization belongs to another account' unless organization.account_id == account.id
  end

  def plan
    if @organization.company_id.present?
      raise Conflict, 'Existing mapping cannot be silently replaced' if @target_company_id && @target_company_id != @organization.company_id
      company = companies.find(@organization.company_id)
      conflicting_deals = @account.jrc_crm_deals.where(organization_id: @organization.id).where.not(company_id: [nil, company.id]).exists?
      conflicting_activities = @account.jrc_crm_activities.where(organization_id: @organization.id).where.not(company_id: [nil, company.id]).exists?
      raise Conflict, 'Mapped organization conflicts with existing CRM company references' if conflicting_deals || conflicting_activities
      return { action: 'mapped', organization_id: @organization.id, company_id: company.id }
    end
    linked = @account.jrc_crm_deals.where(organization_id: @organization.id).where.not(company_id: nil).distinct.pluck(:company_id)
    linked += @account.jrc_crm_activities.where(organization_id: @organization.id).where.not(company_id: nil).distinct.pluck(:company_id)
    linked << @target_company_id if @target_company_id
    tax = attributes[:tax_id]
    linked += companies.where(tax_id: tax).pluck(:id) if tax.present?
    linked.uniq!
    raise Conflict, 'Conflicting company IDs in existing CRM links' if linked.length > 1
    if linked.one?
      company = companies.find(linked.first)
      raise Conflict, 'Conflicting tax identifiers' if tax.present? && company.tax_id.present? && tax != company.tax_id
      return { action: 'link', organization_id: @organization.id, company_id: company.id }
    end
    possible = companies.where('lower(name) = ?', @organization.name.to_s.downcase)
    possible = possible.or(companies.where(domain: @organization.domain.downcase)) if @organization.domain.present?
    raise Conflict, "Select an existing company explicitly: #{possible.limit(20).pluck(:id).join(',')}" if possible.exists?

    candidate = JrcCustomers::Company.new(attributes.merge(account: @account))
    raise Conflict, candidate.errors.full_messages.join('; ') unless candidate.valid?

    { action: 'create', organization_id: @organization.id, attributes: attributes }
  end

  def apply!
    @account.with_lock do
      @organization.reload
      @attributes = nil
      decision = plan
      company = if decision[:action] == 'create'
                  companies.create!(attributes)
                else
                  companies.find(decision.fetch(:company_id))
                end
      if @organization.company_id.nil?
        @organization.update_columns(company_id: company.id)
        JrcCustomers::Audit.record!(account: @account, actor: nil, resource: company,
          event_type: decision[:action] == 'create' ? 'customer_company_created' : 'customer_company_updated',
          to_value: { legacy_organization_id: @organization.id },
          metadata: { source: 'legacy_company_mapping', decision: decision[:action] })
      end
      @account.jrc_crm_deals.where(organization_id: @organization.id, company_id: nil).update_all(company_id: company.id)
      @account.jrc_crm_activities.where(organization_id: @organization.id, company_id: nil).update_all(company_id: company.id)
      company
    end
  end

  private

  def companies
    JrcCustomers::Company.where(account_id: @account.id)
  end

  def attributes
    @attributes ||= begin
      custom = @organization.custom_attributes || {}
      tax = JrcCustomers::TaxIdentifier.normalize(custom['tax_id'].presence || custom['cnpj'].presence || custom['cpf'].presence)
      {
        name: @organization.name, domain: @organization.domain.to_s.strip.downcase.presence,
        description: @organization.description, phone_number: @organization.phone, website: @organization.website,
        owner_id: @organization.owner_id, active: @organization.active, tax_id: tax,
        person_kind: tax&.length == 11 ? 'individual' : 'organization', relationship_type: 'other',
        custom_attributes: custom.deep_dup
      }
    end
  end
end
