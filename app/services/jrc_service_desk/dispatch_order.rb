# frozen_string_literal: true

module JrcServiceDesk::DispatchOrder
  def self.apply(scope)
    deadlines = 'LEFT JOIN (SELECT ticket_id, MIN(due_at) AS due_at FROM jrc_service_desk_sla_clocks ' \
                "WHERE state IN ('running','paused') GROUP BY ticket_id) sd_dispatch_deadlines " \
                'ON sd_dispatch_deadlines.ticket_id = jrc_service_desk_tickets.id'
    order = 'jrc_service_desk_priorities.position ASC, sd_dispatch_deadlines.due_at ASC NULLS LAST, ' \
            'jrc_service_desk_tickets.opened_at ASC, jrc_service_desk_tickets.id ASC'
    scope.joins(:priority).joins(deadlines).order(Arel.sql(order))
  end
end
