# frozen_string_literal: true

module JrcServiceDesk::CaseAssociations
  module_function

  def tickets(row, context)
    scope = Pundit.policy_scope!(context.to_h, JrcServiceDesk::Ticket).where(account_id: row.account_id, unit_id: row.unit_id)
    links = JrcServiceDesk::CaseLink.active.where(account_id: row.account_id, unit_id: row.unit_id, incident_id: row.id).where.not(ticket_id: nil)
    scope.where(incident_id: row.id).or(scope.where(id: links.select(:ticket_id)))
  end

  def related(row, context)
    scope = Pundit.policy_scope!(context.to_h, JrcServiceDesk::Incident).where(unit_id: row.unit_id)
    links = JrcServiceDesk::CaseLink.active.where(account_id: row.account_id, unit_id: row.unit_id)
    row.resource_kind == 'problem' ? scope.where(id: links.where(incident_id: row.id).select(:related_incident_id)) : scope.where(id: links.where(related_incident_id: row.id).select(:incident_id))
  end

  def for_ticket(ticket, context)
    scope = Pundit.policy_scope!(context.to_h, JrcServiceDesk::Incident).where(unit_id: ticket.unit_id)
    links = JrcServiceDesk::CaseLink.active.where(account_id: ticket.account_id, unit_id: ticket.unit_id, ticket_id: ticket.id)
    scope.where(id: links.select(:incident_id)).or(scope.where(id: ticket.incident_id))
  end
end
