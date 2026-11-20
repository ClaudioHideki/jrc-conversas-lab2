# frozen_string_literal: true

# Intersects current native coverage and the artifact's immutable historical scope.
class JrcContactCenter::IvrDraftAccess
  attr_reader :context, :access

  def initialize(context:)
    @context = context.slice(:account, :account_user, :user).transform_values(&:reload)
    @access = JrcContactCenter::AccessScope.new(user_context: @context)
    raise Pundit::NotAuthorizedError unless access.policy.configure?

    @coverage = JrcContactCenter::CorporateCoverage.new(account: @context.fetch(:account), user: @context.fetch(:user))
  end

  def relation
    records = JrcContactCenter::IvrDraft.where(account: context.fetch(:account), unit_id: access.units.select(:id))
    return records if @coverage.group?

    scope = 'jrc_contact_center_ivr_drafts.scope_snapshot'
    companies = @coverage.company_ids.reselect(Arel.sql('companies.id::text')).to_sql
    units = @coverage.unit_ids.reselect(Arel.sql('jrc_crm_business_units.id::text')).to_sql
    records.where(historical_condition(scope, companies, units))
  end

  def find!(id)
    relation.find(id)
  end

  def authorize_unchanged_scope!(draft, unit)
    current_scope = JrcContactCenter::ConfigurationAuditSnapshot.capture(unit).fetch('scope')
    return if draft.scope_snapshot == current_scope

    raise JrcContactCenter::OperationError.new('ivr_scope_changed', status: :conflict)
  end

  private

  def historical_condition(scope, companies, units)
    corporate = <<~SQL.squish
      #{scope} ->> 'issuer_company_id' IN (#{companies}) AND (
        #{scope} ->> 'business_unit_id' IN (#{units}) OR COALESCE(#{scope} ->> 'business_unit_id', '') = '')
    SQL
    return corporate if @coverage.configured?

    "(#{corporate}) OR (COALESCE(#{scope} ->> 'issuer_company_id', '') = '' AND COALESCE(#{scope} ->> 'business_unit_id', '') = '')"
  end
end
