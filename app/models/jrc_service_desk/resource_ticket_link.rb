# frozen_string_literal: true

class JrcServiceDesk::ResourceTicketLink < JrcServiceDesk::TicketRecord
  include JrcServiceDesk::AppendOnly
  belongs_to :operational_resource, class_name: 'JrcServiceDesk::OperationalResource'
  belongs_to :linked_by_membership, class_name: 'JrcServiceDesk::UnitMembership'
  validates :operational_resource_id, uniqueness: { scope: %i[account_id unit_id ticket_id] }
  validate :references_are_consistent

  private

  def references_are_consistent
    %i[operational_resource linked_by_membership].each { |name| validate_unit_reference(name) }
  end
end
