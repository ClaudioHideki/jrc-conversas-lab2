# frozen_string_literal: true

class JrcServiceDesk::ManagerialReportMetrics
  DIMENSIONS = %w[status_id priority_id assignee_membership_id team_id queue_id company_id service_id category_id].freeze

  def initialize(query, now: Time.current)
    @query = query
    @now = now
  end

  def call(total)
    phases = JrcServiceDesk::TicketStatus::PHASES.index_with { 0 }
    groups = @query.relation.joins(:status).group('jrc_service_desk_ticket_statuses.phase', 'jrc_service_desk_ticket_statuses.initial').count
    groups.each { |(phase, _), count| phases[phase] += count }
    new_count = groups.fetch(['open', true], 0)
    { total: total, phases: phases, new_count: new_count, in_service: phases['open'] - new_count,
      open_or_waiting: phases.values_at('open', 'waiting').sum,
      closure_rate: total.positive? ? (100.0 * phases['closed'] / total).round(1) : nil }
      .merge(volume: volume, dimensions: dimensions(total), **JrcServiceDesk::ManagerialReportMeasurements.new(@query, now: @now).summary(total))
  end

  private

  def dimensions(total)
    dimensions = DIMENSIONS.index_with { |field| @query.dimension_counts(field) }
    origins = @query.relation.group(:origin_channel).count.slice(*JrcServiceDesk::ManagerialReportQuery::ORIGINS)
    origins['unknown'] = total - origins.values.sum
    dimensions.merge('origin' => { items: origins.map { |id, count| { id: id, count: count } }, truncated: false },
                     'unit' => { items: [{ id: @query.unit.id.to_s, name: @query.unit.name, count: total }], truncated: false })
  end

  def volume
    expression = JrcServiceDesk::Ticket.sanitize_sql_array(
      ["DATE_TRUNC(?, jrc_service_desk_tickets.#{@query.date_field} AT TIME ZONE 'UTC' AT TIME ZONE ?)::date", @query.group_by, @query.timezone.tzinfo.name]
    )
    bucket = Arel.sql(expression)
    rows = @query.relation.group(bucket).order(Arel.sql("#{expression} DESC")).limit(367).count
    { items: rows.first(366).reverse.map { |day, count| { day: day.to_s, count: count } }, truncated: rows.size > 366 }
  end
end
