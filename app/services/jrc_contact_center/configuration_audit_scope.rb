# frozen_string_literal: true

class JrcContactCenter::ConfigurationAuditScope
  def self.protect_native_list(relation, context)
    ordinary = relation.where.not(comment: JrcContactCenter::ConfigurationAudit::COMMENTS).or(relation.where(comment: nil))
    ordinary.or(new(context: context, relation: relation).call)
  end

  def initialize(context:, relation: Audited.audit_class.all)
    @account = context.fetch(:account)
    @member = context.fetch(:account_user)
    @policy = JrcContactCenter::ModulePolicy.new(context, :contact_center)
    @access = JrcContactCenter::AccessScope.new(user_context: context)
    @organization = JrcContactCenter::OrganizationalScope.new(account: @account, account_user: @member)
    @coverage = JrcCrm::CorporateCoverage.new(account: @account, user: context.fetch(:user))
    @relation = relation
  end

  def call
    return @relation.none unless @policy.audit? && @account.feature_enabled?('audit_logs')

    records = @relation.where(associated_type: 'Account', associated_id: @account.id, comment: JrcContactCenter::ConfigurationAudit::COMMENTS)
    configurations = records.where(comment: JrcContactCenter::ConfigurationAudit::COMMENT)
    configurations = restricted_configurations(configurations) unless @access.full_access? && !@organization.restricted?
    configurations.or(global_records(records))
  end

  private

  def global_records(records)
    return records.none if @organization.restricted?

    roles = records.where(comment: [JrcContactCenter::ConfigurationAudit::ROLE_COMMENT, JrcContactCenter::ConfigurationAudit::AUTHORITY_COMMENT])
    acw = records.where(comment: JrcContactCenter::ConfigurationAudit::ACW_COMMENT, auditable_type: 'Account', auditable_id: @account.id)
    roles.or(acw)
  end

  def scope_json(side)
    "audits.audited_changes -> 'cc_scope' -> '#{side}'"
  end

  def restricted_configurations(records)
    units = @access.units.reselect(Arel.sql('jrc_contact_center_units.id::text')).to_sql
    queues = @access.queues.reselect(Arel.sql('jrc_contact_center_queues.id::text')).to_sql
    %w[before after].each do |side|
      scope = scope_json(side)
      records = records.where("jsonb_typeof(#{scope}) = 'null' OR #{scope} ->> 'unit_id' IN (#{units})")
      records = records.where("jsonb_typeof(#{scope}) = 'null' OR #{scope} ->> 'queue_id' IS NULL OR #{scope} ->> 'queue_id' IN (#{queues})")
      records = historical_coverage(records, scope) if @organization.restricted?
    end
    records
  end

  def historical_coverage(records, scope)
    companies = @coverage.company_ids.reselect(Arel.sql('companies.id::text')).to_sql
    units = @coverage.unit_ids.reselect(Arel.sql('jrc_crm_business_units.id::text')).to_sql
    records.where(<<~SQL.squish)
      jsonb_typeof(#{scope}) = 'null' OR (
        (COALESCE(#{scope} ->> 'issuer_company_id', '') = '' OR #{scope} ->> 'issuer_company_id' IN (#{companies}))
        AND (#{scope} ->> 'business_unit_id' IN (#{units})
          OR (COALESCE(#{scope} ->> 'business_unit_id', '') = '' AND #{scope} ->> 'issuer_company_id' IN (#{companies}))))
    SQL
  end
end
