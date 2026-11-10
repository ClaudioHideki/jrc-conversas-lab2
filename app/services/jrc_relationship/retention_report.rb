# Read-only metric with a frozen initial cohort and native current authorization.
# A lost source or changed scope makes the result unavailable, not a smaller denominator.
class JrcRelationship::RetentionReport
  MAX_CUSTOMERS = 100_000
  def initialize(context)
    @member = context.member
  end

  def call(period:, reference: nil, from: nil, to: nil, portfolio_group_id: nil, compare: true)
    context = JrcRelationship::Context.new(@member)
    start_date, end_date = dates(period, reference, from, to)
    zone = Time.find_zone!(context.formatting.fetch(:timeZone))
    first = zone.local(start_date.year, start_date.month, start_date.day)
    next_date = end_date + 1
    last = zone.local(next_date.year, next_date.month, next_date.day)
    rule = context.configuration.effective_rules['retention_policy']
    return result('configuration_required', context, start_date, end_date) if rule.nil?
    rule = JrcRelationship::RetentionPolicy.normalize!(rule)
    return result('period_not_closed', context, start_date, end_date) if last > Time.current
    group = portfolio_group_id.present? ? JrcRelationship::PortfolioGroupScope.resolve(context).find(portfolio_group_id) : nil
    signature = context.access_signature
    cohort = []
    report = JrcRelationship::RetentionState.transaction(isolation: :repeatable_read) do
      coverage = JrcRelationship::RetentionCoverage.find_by(account_id: context.account.id)
      if !coverage || coverage.started_at > first
        next result('insufficient_history', context, start_date, end_date)
      end
      opening = states(context, first, inclusive: true)
      closing = states(context, last, inclusive: false)
      if opening.size > MAX_CUSTOMERS || closing.size > MAX_CUSTOMERS
        next result('scope_too_large', context, start_date, end_date)
      end
      cohort = opening.select { |row| historical_visible?(context, row, group) && JrcRelationship::RetentionPolicy.eligible?(row, rule) != false }
      complete_access = cohort_authorized?(context, cohort)
      data = JrcRelationship::RetentionMetric.call(opening: cohort, closing: closing, policy: rule, complete: true, authorized: complete_access)
      metadata(context, start_date, end_date).merge(data).merge(policy_version: context.configuration.version,
        coverage_started_at: coverage.started_at.iso8601(6), portfolio_group_id: group&.id)
    end
    fresh = JrcRelationship::Context.new(@member)
    raise Pundit::NotAuthorizedError unless fresh.user.reload.active_for_authentication? && fresh.access_signature == signature
    raise Pundit::NotAuthorizedError if report[:available] && !cohort_authorized?(fresh, cohort)
    if group
      raise Pundit::NotAuthorizedError unless JrcRelationship::PortfolioGroupScope.resolve(fresh).exists?(id: group.id)
    end
    if compare
      previous_first, previous_last = previous_dates(period, start_date, end_date)
      previous = self.class.new(fresh).call(period: 'custom', from: previous_first.iso8601, to: previous_last.iso8601,
        portfolio_group_id: portfolio_group_id, compare: false)
      report[:previous] = previous.slice(:available, :code, :value, :initial, :retained, :exits, :from, :to)
      if report[:available] && previous[:available]
        report[:change_percentage_points] = (report[:value] - previous[:value]).round(2)
      end
      final_context = JrcRelationship::Context.new(@member)
      raise Pundit::NotAuthorizedError unless final_context.access_signature == signature
      raise Pundit::NotAuthorizedError if report[:available] && !cohort_authorized?(final_context, cohort)
    end
    report
  end

  private

  def cohort_authorized?(context, cohort)
    ids = cohort.map { |row| row.fetch('assignment_id') }
    records = context.assignments.where(id: ids).pluck(:id, :company_id, :contact_id).to_h do |id, company_id, contact_id|
      [id, company_id ? "company:#{company_id}" : "contact:#{contact_id}"]
    end
    company_ids = cohort.select { |row| row['customer_type'] == 'company' }.map { |row| row['customer_key'].split(':').last.to_i }
    visible_companies = JrcCrm::CorporateCoverage.new(account: context.account, user: context.user)
      .companies(context.account.master_companies).where(id: company_ids).pluck(:id)
    cohort.all? do |row|
      records[row.fetch('assignment_id')] == row.fetch('customer_key') &&
        (row['customer_type'] != 'company' || visible_companies.include?(row['customer_key'].split(':').last.to_i))
    end
  end

  def previous_dates(period, first, last)
    case period
    when 'monthly' then [first.prev_month.beginning_of_month, first.prev_month.end_of_month]
    when 'quarterly' then [first.prev_month(3).beginning_of_quarter, first.prev_month(3).end_of_quarter]
    when 'annual' then [first.prev_year.beginning_of_year, first.prev_year.end_of_year]
    else
      previous_last = first - 1
      [previous_last - (last - first), previous_last]
    end
  end

  def dates(period, reference, from, to)
    if period == 'custom'
      first, last = exact_date(from), exact_date(to)
    else
      point = exact_date(reference)
      first, last = case period
                    when 'monthly' then [point.beginning_of_month, point.end_of_month]
                    when 'quarterly' then [point.beginning_of_quarter, point.end_of_quarter]
                    when 'annual' then [point.beginning_of_year, point.end_of_year]
                    else raise ArgumentError, 'Select monthly, quarterly, annual or custom retention period'
                    end
    end
    raise ArgumentError, 'Invalid retention period' if last < first || (last - first).to_i > 366
    [first, last]
  end

  def exact_date(value)
    raise ArgumentError, 'Use an explicit calendar date' unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    Date.iso8601(value)
  end

  def states(context, boundary, inclusive:)
    rows = JrcRelationship::RetentionState.where(account_id: context.account.id)
    rows = rows.where("observed_at #{inclusive ? '<=' : '<'} ?", boundary)
    rows.select('DISTINCT ON (customer_key) jrc_relationship_retention_states.*').order(:customer_key, observed_at: :desc, id: :desc)
        .limit(MAX_CUSTOMERS + 1).map(&:facts)
  end

  def historical_visible?(context, row, group)
    return false if group && !Array(row['portfolio_ids']).include?(group.id)
    return true if context.policy.admin?
    return true if row['owner_id'] == context.user.id
    return false unless context.policy.team?
    teams = @teams ||= TeamMember.where(user_id: context.user.id, team_id: context.account.teams.select(:id)).pluck(:team_id)
    teams.include?(row['team_id'])
  end

  def metadata(context, from, to)
    { metric: 'TRR', name: 'Taxa de Retencao de Relacionamento', from: from.iso8601, to: to.iso8601,
      timezone: context.formatting.fetch(:timeZone), historical: true }
  end

  def result(code, context, from, to)
    metadata(context, from, to).merge(JrcRelationship::RetentionMetric.unavailable(code))
  end
end
