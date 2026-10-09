# frozen_string_literal: true

class JrcServiceDesk::DashboardService
  def initialize(user_context:)
    @user_context = user_context
  end

  def call(parameters: {})
    Pundit.authorize(@user_context, :service_desk, :dashboard?, policy_class: JrcServiceDesk::ModulePolicy)
    query = JrcServiceDesk::TicketQuery.new(user_context: @user_context, parameters: parameters)
    # One grouped SQL query supplies all related counts: no independent cached totals.
    groups = query.relation.joins(:status).group('jrc_service_desk_ticket_statuses.id',
                                                 'jrc_service_desk_ticket_statuses.name',
                                                 'jrc_service_desk_ticket_statuses.phase').count
    supervision = JrcServiceDesk::SupervisionProjection.new(context: @user_context, relation: query.relation).call
    unavailable = %w[csat]
    unavailable += %w[sla_breached time_series] unless supervision
    unavailable << 'sla_breached' if supervision && !supervision[:sla]
    JrcServiceDesk::KpiCounts.call(groups).merge(
      generated_at: Time.current.iso8601(6), filters: query.parameters.values.except('page', 'per_page', 'sort'),
      supervision: supervision, unavailable: unavailable
    )
  end
end
