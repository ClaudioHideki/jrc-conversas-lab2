# frozen_string_literal: true

# Conservative, exact structured suggestions. Never performs automatic grouping.
class JrcServiceDesk::RecurrenceProjection
  MAX_TICKETS = 2000

  def initialize(context:, unit:)
    @context = context
    @unit = unit
  end

  def call
    raise Pundit::NotAuthorizedError unless @context.unit_allowed?(@unit) && @context.capability?(:incidents_manage)

    version = JrcServiceDesk::OperationalRuleVersion.current(account_id: @context.account.id, unit_id: @unit.id, kind: 'recurrence')
    return { enabled: false, groups: [], truncated: false } unless version&.enabled?
    raise JrcServiceDesk::IdempotencyConflict unless version.digest == version.expected_digest

    definition = version.definition
    JrcServiceDesk::OperationalRuleContract.validate!('recurrence', definition)
    authorize_dimensions!(definition)
    observed = Time.current
    rows = JrcServiceDesk::TicketPolicy::Scope.new(@context.to_h, JrcServiceDesk::Ticket).resolve
                                              .where(unit_id: @unit.id, opened_at: (observed - (definition.fetch('window_days') * 86_400))..observed)
                                              .order(opened_at: :desc, id: :desc).limit(MAX_TICKETS + 1).to_a
    groups = JrcServiceDesk::RecurrenceGrouping.call(rows.first(MAX_TICKETS).map { |row| attributes(row) }, definition)
    { enabled: true, rule_version_id: version.id.to_s, rule_digest: version.digest, observed_at: observed.iso8601(6),
      window_basis: 'rolling_24_hour_days', truncated: rows.size > MAX_TICKETS, inspected: [rows.size, MAX_TICKETS].min, groups: groups }
  end

  private

  def authorize_dimensions!(definition)
    return unless definition.fetch('group_by').include?('company_id')

    raise Pundit::NotAuthorizedError unless @context.capability?(:customers_view)

    Pundit.authorize(@context.to_h, :directory, :access?, policy_class: JrcCustomers::DirectoryPolicy)
  end

  def attributes(ticket)
    ticket.attributes.slice('id', 'company_id', 'service_id', 'category_id', 'ticket_type_id', 'incident_id').merge('title' => ticket.title)
  end
end
