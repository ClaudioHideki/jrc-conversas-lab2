# Financial membership uses only records visible through the native CRM scope.
# A missing permission is an access denial, never a zero financial balance.
class JrcCustomers::FinancialSegmentCriteria
  FIELDS = %w[invoiced_revenue active_contract_count].freeze
  OPERATORS = { 'equal_to' => :eq, 'not_equal_to' => :not_eq, 'greater_than' => :gt,
                'at_least' => :gteq, 'less_than' => :lt, 'at_most' => :lteq }.freeze

  def self.error(rule)
    return 'contains an unsupported financial operator' unless OPERATORS.key?(rule['operator'])

    pattern = rule['field'] == 'invoiced_revenue' ? /\A[0-9]{1,12}(\.[0-9]{1,2})?\z/ : /\A[0-9]{1,9}\z/
    return 'requires a nonnegative financial value' unless rule['value'].is_a?(String) && rule['value'].match?(pattern)

    if rule['field'] == 'active_contract_count'
      return 'contract counts do not accept a period' if rule.keys.intersect?(%w[period_start period_end])

      return nil
    end
    period_error(rule)
  end

  def self.period_error(rule)
    from, to = rule.values_at('period_start', 'period_end')
    valid_dates = [from, to].all? { |date| date.is_a?(String) && date.match?(/\A(?!0000)\d{4}-\d{2}-\d{2}\z/) }
    return 'invoiced revenue requires ISO start and end dates' unless valid_dates
    return 'invalid invoiced revenue period' unless Date.iso8601(from) <= Date.iso8601(to)

    nil
  rescue Date::Error
    'invalid invoiced revenue period'
  end

  def initialize(account:, actor:, scope:)
    @account = account
    @actor = actor
    @scope = scope
  end

  def call(rule)
    relation, aggregate, value = financial_source(rule, authorized_visibility)
    company = Contact.arel_table[:company_id]
    relation = relation.joins(:contact).where(contacts: { account_id: @account.id }).where.not(contacts: { company_id: nil }).reorder(nil)
    grouped = relation.group(company).having(Arel.sql(aggregate).public_send(OPERATORS.fetch(rule['operator']), value)).reselect(company)
    matched = @scope.where(id: grouped)
    # Missing authorized sources contribute zero, preserving the original scalar
    # aggregate semantics without rescanning the entire source for each company.
    matches_zero?(rule['operator'], value) ? matched.or(@scope.where.not(id: relation.reselect(company))) : matched
  end

  private

  def matches_zero?(operator, value)
    { 'equal_to' => value.zero?, 'not_equal_to' => value.positive?, 'greater_than' => false,
      'at_least' => value.zero?, 'less_than' => value.positive?, 'at_most' => true }.fetch(operator)
  end

  def authorized_visibility
    JrcCustomers::ContactDirectory.new(account: @account, actor: @actor).authorize!
    member = AccountUser.find_by!(account_id: @account.id, user_id: @actor.id)
    visibility = JrcCustomers::Visibility.new(account: @account, user: @actor, account_user: member)
    raise Pundit::NotAuthorizedError unless visibility.crm?

    visibility
  end

  def financial_source(rule, visibility)
    if rule['field'] == 'active_contract_count'
      relation = visibility.crm(@account.jrc_crm_contracts).where(status: %w[active expiring])
      return [relation, 'COUNT(*)', rule['value'].to_i]
    end

    relation = visibility.crm(@account.jrc_crm_sales_orders)
                         .where(status: JrcCrm::GoalProgressService::ORDER_STATUSES.fetch('invoiced_orders'))
    from, to = Time.use_zone(Time.find_zone(@account.reporting_timezone) || Time.zone) do
      [Date.iso8601(rule['period_start']).beginning_of_day, Date.iso8601(rule['period_end']).end_of_day]
    end
    date_sql = 'COALESCE(jrc_crm_sales_orders.sold_at, jrc_crm_sales_orders.closed_at, jrc_crm_sales_orders.created_at) BETWEEN ? AND ?'
    relation = relation.where(date_sql, from, to)
    [relation, 'COALESCE(SUM(jrc_crm_sales_orders.total_cents), 0)', (BigDecimal(rule['value']) * 100).to_i]
  end
end
