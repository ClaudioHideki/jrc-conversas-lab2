module JrcCrm
  # A restrictive boundary only. It never grants records that the existing CRM
  # visibility rules did not already return. Roles do not grant corporate coverage.
  class OrganizationalVisibility
    SETTINGS_KEY = JrcCrm::OrganizationalStructureService::SETTINGS_KEY

    def initialize(account:, user:, relation:, include_company: true)
      @account = account
      @user = user
      @relation = relation
      @include_company = include_company
    end

    def call
      bounded = JrcCrm::CorporateCoverage.new(account: account, user: user).restrict(relation)
      return bounded unless enabled?

      scopes = account.jrc_crm_user_business_units.structure_managed.active.where(user_id: user.id)
      return bounded unless scopes.exists?
      return bounded if scopes.where(scope: 'GROUP').exists?

      company_ids = scopes.where(scope: 'COMPANY').where.not(company_id: nil).distinct.pluck(:company_id)
      direct_unit_ids = scopes.where(scope: 'BUSINESS_UNIT').where.not(business_unit_id: nil).distinct.pluck(:business_unit_id)
      company_unit_ids = account.jrc_crm_business_units.where(company_id: company_ids).pluck(:id)
      allowed_unit_ids = (direct_unit_ids + company_unit_ids).uniq

      # CRM company_id is the customer, never the issuer. Issuer scope uses the unit.
      company_column = @include_company && relation.klass.table_name == 'companies'
      unit_column = relation.klass.column_names.include?('business_unit_id')
      return bounded unless company_column || unit_column

      table = relation.klass.arel_table
      condition = nil
      condition = combine(condition, table[:company_id].in(company_ids)) if company_column && company_ids.any?
      condition = combine(condition, table[:business_unit_id].in(allowed_unit_ids)) if unit_column && allowed_unit_ids.any?

      condition ? bounded.where(condition) : relation.none
    end

    def allowed_business_unit_ids
      if account.master_companies.exists?(relationship_type: 'internal')
        return account.jrc_crm_business_units.where(id: JrcCrm::CorporateCoverage.new(account: account, user: user).unit_ids).pluck(:id)
      end

      legacy_business_unit_ids
    end

    private

    attr_reader :account, :user, :relation

    def legacy_business_unit_ids
      return nil unless enabled?

      scopes = account.jrc_crm_user_business_units.structure_managed.active.where(user_id: user.id)
      return nil unless scopes.exists?
      return nil if scopes.where(scope: 'GROUP').exists?

      company_ids = scopes.where(scope: 'COMPANY').where.not(company_id: nil).pluck(:company_id)
      (scopes.where(scope: 'BUSINESS_UNIT').where.not(business_unit_id: nil).pluck(:business_unit_id) +
        account.jrc_crm_business_units.where(company_id: company_ids).pluck(:id)).uniq
    end

    def enabled?
      settings = account.custom_attributes.fetch(SETTINGS_KEY, {})
      settings.is_a?(Hash) && ActiveModel::Type::Boolean.new.cast(settings['scope_enforcement_enabled'])
    end

    def combine(current, extra)
      current ? current.or(extra) : extra
    end
  end
end
