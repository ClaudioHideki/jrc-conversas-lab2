module JrcCrm
  # CompanyAdapter allows the CRM module to work seamlessly with:
  # 1. Chatwoot Enterprise `Company` model (if available and licensed)
  # 2. Native `JrcCrm::Organization` model (independent standalone fallback)
  #
  # This guarantees zero hard dependency on Enterprise code and 100% redistribution safety.
  class CompanyAdapter
    def self.enterprise_company_available?(account)
      defined?(::Company) && account.respond_to?(:companies) && account.feature_enabled?('companies') rescue false
    end

    def self.find_or_create(account:, name:, attributes: {})
      if account.feature_enabled?('jrc_customer_master')
        values = attributes.with_indifferent_access
        scope = JrcCustomers::Company.where(account_id: account.id)
        company = scope.find(values[:company_id]) if values[:company_id].present?
        tax_id = JrcCustomers::TaxIdentifier.normalize(values[:tax_id])
        company ||= scope.find_by(tax_id: tax_id) if tax_id.present?
        if company.nil? && scope.where('lower(name) = ?', name.to_s.downcase).exists?
          raise JrcCustomers::LegacyCompanyMapper::Conflict, 'Select company_id explicitly; a matching name is not proof of identity'
        end
        company ||= scope.create!(values.slice(:domain, :description, :phone_number, :website, :tax_id).merge(name: name, relationship_type: 'prospect'))
        return { type: :master_company, record: company, id: company.id }
      end
      if enterprise_company_available?(account)
        company = account.companies.find_or_initialize_by(name: name)
        company.assign_attributes(attributes.slice(:domain, :description, :phone_number, :website))
        company.save! if company.new_record? || company.changed?
        { type: :enterprise_company, record: company, id: company.id }
      else
        org = account.jrc_crm_organizations.find_or_initialize_by(name: name)
        org.assign_attributes(attributes.slice(:domain, :description, :phone, :website, :custom_attributes))
        org.save! if org.new_record? || org.changed?
        { type: :crm_organization, record: org, id: org.id }
      end
    end

    def self.resolve_entity(account:, organization_id: nil, company_id: nil)
      if account.feature_enabled?('jrc_customer_master')
        return JrcCustomers::Company.where(account_id: account.id).find(company_id) if company_id.present?
        return nil if organization_id.blank?

        organization = account.jrc_crm_organizations.find(organization_id)
        return JrcCustomers::Company.where(account_id: account.id).find_by(id: organization.company_id)
      end
      if organization_id.present?
        account.jrc_crm_organizations.find_by(id: organization_id)
      elsif company_id.present? && enterprise_company_available?(account)
        account.companies.find_by(id: company_id)
      else
        nil
      end
    end
  end
end
