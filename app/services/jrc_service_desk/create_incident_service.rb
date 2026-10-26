# frozen_string_literal: true

class JrcServiceDesk::CreateIncidentService < JrcServiceDesk::BaseService
  def call(unit_id:, attributes:, idempotency_key:)
    values = JrcServiceDesk::CaseInput.call(attributes, creating: true)
    ids = ticket_ids(values)
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    fingerprint = JrcServiceDesk::CanonicalJson.digest(JrcServiceDesk::RecordedChanges.call(values.merge('ticket_ids' => ids)))
    with_unit(unit_id) do |unit|
      raise Pundit::NotAuthorizedError unless context.capability?(:incidents_manage)

      tickets = authorized_tickets(unit, ids)
      existing = authorized_replay(unit, key, fingerprint)
      next existing if existing

      row = build_incident(unit, tickets, values)
      row.assign_attributes(idempotency_key: key, request_fingerprint: fingerprint)
      authorize!(row, :create?)
      row.save!
      link_tickets(tickets, row)
      JrcServiceDesk::CaseJournal.append!(row: row, actor: actor_membership, event: 'created', key: key, fingerprint: fingerprint,
                                          data: { 'title' => row.title, 'status' => row.status, 'ticket_ids' => ids.map(&:to_s) })
      row
    end
  end

  private

  def link_tickets(tickets, incident)
    tickets.each do |ticket|
      ticket.update!(incident: incident) unless ticket.incident_id
      incident.case_links.create!(account: context.account, unit: ticket.unit, ticket: ticket, created_by_membership: actor_membership)
      append_event!(ticket, 'incident_linked', 'incident_id' => incident.id, 'primary_ticket_id' => incident.primary_ticket_id)
    end
  end

  def ticket_ids(values)
    ids = values.fetch('ticket_ids', [])
    raise ArgumentError unless ids.is_a?(Array) && ids.size <= 200

    ids.map { |id| JrcServiceDesk::Input.id(id) }.uniq.sort
  end

  def authorized_tickets(unit, ids)
    ids.map do |id|
      JrcServiceDesk::TicketPolicy::Scope.new(context.to_h, JrcServiceDesk::Ticket).resolve.where(unit_id: unit.id).lock.find(id).tap do |ticket|
        authorize!(ticket, :update?)
      end
    end
  end

  def authorized_replay(unit, key, fingerprint)
    existing = JrcServiceDesk::Incident.find_by(account_id: context.account.id, unit_id: unit.id,
                                                created_by_membership_id: actor_membership.id, idempotency_key: key)
    return unless existing

    authorize!(existing, :show?)
    raise JrcServiceDesk::IdempotencyConflict unless existing.request_fingerprint == fingerprint

    existing
  end

  def build_incident(unit, tickets, values)
    JrcServiceDesk::Incident.new(
      account: context.account, unit: unit, created_by_membership: actor_membership, primary_ticket: tickets.first,
      title: values.fetch('title'), description: values['description'], impact: values['impact'],
      cause: values['cause'], workaround: values['workaround'], resolution: values['resolution'],
      severity: values.fetch('severity'), started_at: values.fetch('started_at', Time.current),
      service: reference(JrcServiceDesk::Service, values['service_id'], unit),
      category: reference(JrcServiceDesk::Category, values['category_id'], unit), details: values.fetch('details', {}),
      resource_kind: values.fetch('resource_kind', 'incident'), owner_membership: assignee(values['owner_account_user_id'], unit)
    )
  end
end
