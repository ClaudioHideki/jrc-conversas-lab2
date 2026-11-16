# Intersects operational queues/units with the existing corporate coverage.
# An unmapped operational unit is not a business-unit grant.
class JrcContactCenter::OrganizationalScope
  def initialize(account:, account_user:)
    @account = account
    @coverage = JrcCrm::CorporateCoverage.new(account: account, user: account_user.user)
  end

  def restricted?
    @coverage.configured? && !@coverage.group?
  end

  def units
    relation = JrcContactCenter::Unit.where(account: @account)
    return relation unless restricted?

    units = @coverage.unit_ids.pluck(:id).map(&:to_s)
    companies = @coverage.company_ids.pluck(:id).map(&:to_s)
    relation.where("settings ->> 'business_unit_id' IN (?)", units)
            .or(relation.where("settings ->> 'issuer_company_id' IN (?) AND COALESCE(settings ->> 'business_unit_id', '') = ''", companies))
  end

  def records(relation, unit_column:, queue_column:)
    return relation unless restricted?

    permitted_units = units.select(:id)
    permitted_queues = JrcContactCenter::Queue.where(account: @account, unit_id: permitted_units).select(:id)
    queue_ok = relation.where(queue_column => nil).or(relation.where(queue_column => permitted_queues))
    return queue_ok.where.not(queue_column => nil) unless unit_column

    unit_ok = relation.where(unit_column => nil).or(relation.where(unit_column => permitted_units))
    bound = relation.where.not(unit_column => nil).or(relation.where.not(queue_column => nil))
    unit_ok.merge(queue_ok).merge(bound)
  end

  def authorize_links!(settings)
    company_id = settings['issuer_company_id'].presence
    unit_id = settings['business_unit_id'].presence
    JrcApprovals::Authorization.scope!(@account, company_id, unit_id)
    return unless restricted?

    allowed = unit_id ? @coverage.unit_allowed?(unit_id) : company_id && @coverage.company_allowed?(company_id)
    raise Pundit::NotAuthorizedError unless allowed
  end
end
