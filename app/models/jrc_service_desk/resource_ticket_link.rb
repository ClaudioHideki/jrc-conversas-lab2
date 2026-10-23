# frozen_string_literal: true

class JrcServiceDesk::ResourceTicketLink < JrcServiceDesk::TicketRecord
  include JrcServiceDesk::AppendOnly
  belongs_to :operational_resource, class_name: 'JrcServiceDesk::OperationalResource'
  belongs_to :linked_by_membership, class_name: 'JrcServiceDesk::UnitMembership'
  validates :operational_resource_id, uniqueness: { scope: %i[account_id unit_id ticket_id] }
  validate :references_are_consistent

  # The immutable link is retained for audit; the last explicit link event is authoritative.
  scope :active, lambda {
    where(<<~SQL.squish)
      COALESCE((
        SELECT events.event_type FROM jrc_service_desk_ticket_events events
        WHERE events.account_id = jrc_service_desk_resource_ticket_links.account_id
          AND events.unit_id = jrc_service_desk_resource_ticket_links.unit_id
          AND events.ticket_id = jrc_service_desk_resource_ticket_links.ticket_id
          AND events.event_type IN ('resource_linked', 'resource_unlinked')
          AND events.data ->> 'resource_id' = jrc_service_desk_resource_ticket_links.operational_resource_id::text
        ORDER BY events.id DESC LIMIT 1
      ), 'resource_linked') = 'resource_linked'
    SQL
  }

  private

  def references_are_consistent
    %i[operational_resource linked_by_membership].each { |name| validate_unit_reference(name) }
  end
end
