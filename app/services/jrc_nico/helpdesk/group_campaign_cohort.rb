# frozen_string_literal: true

# Exact incident requesters, never the account-wide campaign audience.
class JrcNico::Helpdesk::GroupCampaignCohort
  attr_reader :incident, :tickets, :contacts

  def initialize(context, event, incident_id)
    @context, @event = context, event
    @incident = JrcNico::DomainAccess.authorize_resource!(context.access, 'JrcServiceDesk::Incident', incident_id)
    @tickets = incident.tickets.order(:id).to_a
    expected = event.evidence.fetch('ticket_ids').sort
    unless tickets.map(&:id) == expected && tickets.any? && tickets.size <= 200
      raise Pundit::NotAuthorizedError
    end
    @contacts = tickets.map { |ticket| authorized_contact(ticket) }.uniq(&:id).sort_by(&:id)
  end

  def source
    { 'incident_id' => incident.id, 'ticket_ids' => tickets.map(&:id), 'contact_ids' => contacts.map(&:id),
      'cohort_digest' => JrcNico::Helpdesk::Definition.digest(entries), 'eligibility_digest' => eligibility_digest }
  end

  def resources
    [['JrcServiceDesk::Incident', incident.id]] + tickets.flat_map do |ticket|
      [['JrcServiceDesk::Ticket', ticket.id], ['JrcNico::ServiceTicketCustomer', ticket.id], ['Contact', ticket.requester_id]]
    end
  end

  def entries
    contacts.map do |contact|
      { 'name' => contact.name, 'phone' => contact.phone_number, 'contact_id' => contact.id,
        'ticket_ids' => tickets.select { |ticket| ticket.requester_id == contact.id }.map(&:id) }
    end
  end

  private

  def authorized_contact(ticket)
    raise Pundit::NotAuthorizedError unless ticket.unit_id == incident.unit_id && ticket.unit_id == @context.ticket(@event.ticket_id).unit_id

    @context.ticket(ticket.id)
    Pundit.authorize(@context.native.to_h, ticket, :view_customer?)
    contact = @context.access.contact(ticket.requester_id)
    unless contact.account_id == @context.account.id && contact.company_id == ticket.company_id
      raise Pundit::NotAuthorizedError
    end
    contact
  end

  def eligibility_digest
    phones = contacts.map { |contact| JrcCampaigns::PhoneNormalizer.call(contact.phone_number) }.uniq.sort
    account = @context.account
    value = { 'blacklisted' => account.jrc_campaign_blacklists.where(phone_number: phones).order(:phone_number).pluck(:phone_number),
      'consented' => JrcCampaigns::Consent.active.where(account: account, phone_number: phones).order(:phone_number).pluck(:phone_number),
      'blocked' => contacts.select(&:blocked?).map(&:id) }
    JrcNico::Helpdesk::Definition.digest(value)
  end
end
