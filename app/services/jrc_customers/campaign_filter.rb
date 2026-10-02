class JrcCustomers::CampaignFilter
  FIELDS = %w[company_id segment relationship_type department].freeze
  class InvalidFilter < StandardError; end

  def self.apply(scope:, account:, filters:)
    raise InvalidFilter, 'Customer filters must be an object' unless filters.is_a?(Hash)
    values = filters.with_indifferent_access
    return scope if values.empty? || values.values.all?(&:blank?)
    raise InvalidFilter, 'Customer master is not enabled' unless account.feature_enabled?('jrc_customer_master')
    raise InvalidFilter, 'Unsupported customer filter' if (values.keys.map(&:to_s) - FIELDS).any?

    companies = account.master_companies
    companies = companies.where(id: account.master_companies.find(values[:company_id]).id) if values[:company_id].present?
    companies = companies.where(segment: values[:segment]) if values[:segment].present?
    if values[:relationship_type].present?
      raise InvalidFilter, 'Invalid company relationship' unless JrcCustomers::CompanyRules::RELATIONSHIPS.include?(values[:relationship_type])
      companies = companies.where(relationship_type: values[:relationship_type])
    end
    filtered = scope.where(account_id: account.id)
    filtered = filtered.where(company_id: companies.select(:id)) if values.except(:department).values.any?(&:present?)
    filtered = filtered.where(department: values[:department]) if values[:department].present?
    filtered
  end
end
