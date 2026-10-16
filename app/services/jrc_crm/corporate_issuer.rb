# Resolves existing native units and companies; never uses the document's customer company_id.
class JrcCrm::CorporateIssuer
  def self.authorize!(account:, user:, unit:)
    coverage = JrcCrm::CorporateCoverage.new(account: account, user: user)
    raise JrcApprovals::Error, 'ISSUER_UNIT_REQUIRED' if issuer_missing?(coverage, unit)
    return unless unit
    raise ActiveRecord::RecordNotFound unless unit.account_id == account.id
    return unless unit.company_id

    raise Pundit::NotAuthorizedError unless coverage.unit_allowed?(unit.id)
  end

  def self.issuer_missing?(coverage, unit)
    coverage.configured? && !unit&.company_id
  end
  private_class_method :issuer_missing?

  def self.authorize_resource!(resource, user)
    authorize!(account: resource.account, user: user, unit: JrcApprovals::CommercialCatalog.business_unit(resource))
  end

  def self.approval_resource!(account, user, key, id)
    entry = JrcApprovals::Catalog.fetch(key)
    resource = entry.model.where(account_id: account.id).find(id)
    raise Pundit::NotAuthorizedError unless entry.authorize.call(user, resource)

    unit = JrcApprovals::CommercialCatalog.business_unit(resource)
    raise JrcApprovals::Error, 'ISSUER_UNIT_REQUIRED' unless unit

    authorize!(account: account, user: user, unit: unit)
    JrcApprovals::Authorization.new(account: account, user: user)
                               .authorize!('request_create', company_id: unit.company_id, unit_id: unit.id)
    resource
  end

  def self.product!(account:, user:, id:, unit:)
    product = JrcCrm::CorporateCoverage.new(account: account, user: user).restrict(account.jrc_crm_products).active.find(id)
    raise ActiveRecord::RecordNotFound, 'product belongs to another issuer unit' if product.business_unit_id && product.business_unit_id != unit&.id

    product
  end

  def self.attributes(unit)
    company = unit&.operating_company
    return {} unless company

    { issuer_company_name: company.name, issuer_tax_id: company.tax_id, issuer_unit: unit.name }
  end

  def self.document_name(record, order, snapshot)
    unit = record.try(:business_unit) || order.try(:business_unit)
    company = unit&.operating_company
    return company.name if company

    legacy_document_name(record, order, snapshot)
  end

  def self.legacy_document_name(record, order, snapshot)
    record.try(:issuer_company_name).presence || order.try(:business_unit)&.name || snapshot[:company_name] || JrcCrm::DocumentBranding::NAME
  end
  private_class_method :legacy_document_name

  def self.reference(proposal)
    { issuer_company_id: proposal.business_unit&.company_id, business_unit_id: proposal.business_unit_id }
  end

  def self.payload(proposal)
    unit = proposal.business_unit
    company = unit&.operating_company
    return { company_name: proposal.issuer_company_name, tax_id: proposal.issuer_tax_id, unit: proposal.issuer_unit } unless company

    { company_id: company.id, company_name: company.name, tax_id: company.tax_id, unit: unit.name,
      legal_name: JrcCrm::CorporateProfile.read(company)['legal_name'] }
  end
end
