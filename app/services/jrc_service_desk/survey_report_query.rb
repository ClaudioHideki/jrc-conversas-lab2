# frozen_string_literal: true

# Service Desk is a view of the shared survey engine, not a second survey store.
class JrcServiceDesk::SurveyReportQuery
  FIELDS = %w[unit_id service_id company_id type from to period_basis record_status page per_page].freeze
  attr_reader :context, :operational, :unit, :scope, :filters, :timezone

  def initialize(user_context:, parameters:)
    @operational = JrcServiceDesk::OperationalContext.new(user_context)
    raise Pundit::NotAuthorizedError unless operational.capability?(:tickets_view) && operational.capability?(:customers_view)

    @context = JrcRelationship::Context.new(operational.account_user)
    @filters = JrcServiceDesk::Input.attributes(parameters, FIELDS)
    @unit = operational.unit_scope.find(JrcServiceDesk::Input.id(filters.fetch('unit_id')))
    @timezone = (Time.find_zone(context.account.reporting_timezone) || Time.zone).tzinfo.name
    @tickets = JrcServiceDesk::TicketPolicy::Scope.new(operational.to_h, JrcServiceDesk::Ticket).resolve_for('customers_view').where(unit_id: unit.id)
    if filters['service_id'].present?
      service = JrcServiceDesk::Service.where(account_id: unit.account_id, unit_id: unit.id).find(JrcServiceDesk::Input.id(filters['service_id']))
      @tickets = @tickets.where(service_id: service.id)
    end
    if filters['company_id'].present?
      raise Pundit::NotAuthorizedError unless JrcCustomers::DirectoryPolicy.new(operational.to_h, :directory).access?

      @tickets = @tickets.where(company_id: JrcServiceDesk::Input.id(filters['company_id']))
    end
    @report = JrcRelationship::SurveyReport.new(context,
                                                filters.except('service_id', 'page', 'per_page').merge('source_type' => 'JrcServiceDesk::Ticket'))
    @scope = Time.use_zone(timezone) { visible(@report.scope(action: 'report')) }
  end

  def visible(rows)
    JrcRelationship::SurveyModelAccess.visible_scope(context, rows, action: 'report', share: 'share_reports')
                                      .where(source_type: 'JrcServiceDesk::Ticket', source_id: @tickets.select(:id))
  end

  def summary
    Time.use_zone(timezone) do
      JrcRelationship::SurveySummary.new(context, scope, selected_period: filters['from'].present?,
                                                         cohort: visible(@report.cohort_scope), cohort_available: @report.cohort_available?,
                                                         cohort_period: @report.cohort_period).call
    end
  end

  def answered
    scope.where.not(responded_at: nil)
  end

  def distribution
    scale = JrcRelationship::SurveyScale.sql('csat')
    counts = answered.where(kind: 'csat').where.not(score: nil).group(Arel.sql("ROUND((#{scale})::numeric)")).count
    (1..5).map { |score| { score: score, count: counts.fetch(score.to_d, 0) } }
  end

  def services
    scale = JrcRelationship::SurveyScale.sql('csat')
    answered.where(kind: 'csat').where.not(score: nil)
            .joins('INNER JOIN jrc_service_desk_tickets report_ticket ON report_ticket.id = jrc_relationship_surveys.source_id ' \
                   'AND report_ticket.account_id = jrc_relationship_surveys.account_id')
            .group('report_ticket.service_id').order(Arel.sql("AVG(#{scale}) ASC")).limit(10)
            .pluck(Arel.sql('report_ticket.service_id'), Arel.sql("AVG(#{scale})"), Arel.sql('COUNT(*)')).map do |id, average, count|
      service = JrcServiceDesk::Service.find_by(account_id: context.account.id, unit_id: unit.id, id: id)
      { service_id: id&.to_s, name: service&.name, csat: average.to_f, responses: count }
    end
  end

  def responses(limit: 10, offset: 0)
    presenter = JrcServiceDesk::Presenter.new(user_context: operational.to_h, read_only: true)
    responses = answered.order(responded_at: :desc, id: :desc).limit(limit).offset(offset).to_a
    tickets = @tickets.where(id: responses.map(&:source_id)).index_by(&:id)
    responses.filter_map do |row|
      ticket = tickets[row.source_id]
      next unless ticket

      record = presenter.ticket(ticket)
      score = row.kind == 'csat' && row.score ? normalized_csat(row) : row.score
      { id: row.id.to_s, ticket_id: ticket.id.to_s, ticket_number: record[:number], title: record[:title],
        company: record[:company], service: record[:service], kind: row.kind, score: score,
        comment: row.comment, responded_at: row.responded_at.iso8601(6) }
    end
  end

  def normalized_csat(row)
    model = row.definition_snapshot.dig('settings', 'service_desk_model')
    model ? JrcRelationship::SurveyScale.normalize(row.score, row.questions.first, low: 1, high: 5) : row.score
  end
end
