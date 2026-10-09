# frozen_string_literal: true

# Adds search ONLY to a relation already authorized by TicketPolicy/PortalScope.
class JrcServiceDesk::TicketSearch
  MAX_ID = (2**63) - 1

  def self.identifier(query)
    value = query.to_s.strip.delete_prefix('#')
    return unless value.match?(/\A[1-9][0-9]{0,18}\z/)

    number = value.to_i
    number if number <= MAX_ID
  end

  def self.apply(scope, query)
    raise ArgumentError, 'Invalid search' unless query.is_a?(String) && query.length <= 200

    value = query.strip
    return scope if value.empty?

    title = 'jrc_service_desk_tickets.title ILIKE :query'
    number = identifier(value)
    statement = number ? "(jrc_service_desk_tickets.id = :number OR #{title})" : title
    scope.where(statement, number: number, query: "%#{JrcServiceDesk::Ticket.sanitize_sql_like(value)}%")
  end
end
