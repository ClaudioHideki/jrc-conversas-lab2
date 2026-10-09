# frozen_string_literal: true

# WebsiteTokenHelper establishes the native browser identity. Portal access also
# proves the current contact identifier; a verification flag surviving a merge
# cannot authorize the merged contact's tickets.
class JrcServiceDesk::PortalScope
  attr_reader :contact

  def initialize(contact_inbox:, identity_proof:)
    @identity = ContactInbox.find(contact_inbox.id)
    @contact = @identity.contact
    @account = @identity.inbox.account
    identity_proof.verify!(identity: @identity)
    raise Pundit::NotAuthorizedError unless @identity.hmac_verified? && @account.active? && @account.feature_enabled?('jrc_service_desk') &&
                                            @contact.account_id == @account.id && !@contact.blocked?
  end

  def conversations
    verified = @contact.contact_inboxes.where(inbox_id: @identity.inbox_id, hmac_verified: true).select(:id)
    @account.conversations.where(contact_id: @contact.id, contact_inbox_id: verified)
  end

  def services
    records = JrcServiceDesk::Service.where(account_id: @account.id, active: true, portal_enabled: true, portal_inbox_id: @identity.inbox_id)
                                     .joins(unit: :operator_company)
                                     .where(jrc_service_desk_units: { active: true }, jrc_service_desk_operator_companies: { active: true })
                                     .joins(:portal_execution_membership).where(jrc_service_desk_unit_memberships: { active: true })
    allowed = records.select { |service| JrcServiceDesk::PortalCatalogue.new(contact: @contact, service: service).allowed? }
    records.where(id: allowed.map(&:id))
  end

  def tickets
    links = JrcServiceDesk::TicketConversation.where(account_id: @account.id, conversation_id: conversations.select(:id)).select(:ticket_id)
    scope = JrcServiceDesk::Ticket.where(account_id: @account.id, requester_id: @contact.id, id: links)
                                  .joins(unit: :operator_company)
                                  .where(jrc_service_desk_units: { active: true }, jrc_service_desk_operator_companies: { active: true })
                                  .left_outer_joins(:service)
                                  .joins(:status)
    tickets_with_access(scope)
  end

  def notes(ticket)
    JrcServiceDesk::InteractionVisibility.portal_scope(ticket.ticket_notes.where(account_id: @account.id, unit_id: ticket.unit_id))
  end

  def tasks(ticket)
    JrcServiceDesk::InteractionVisibility.portal_scope(ticket.ticket_tasks.where(account_id: @account.id, unit_id: ticket.unit_id))
  end

  def knowledge(query = '')
    raise ArgumentError unless query.is_a?(String) && query.size <= 200
    return Article.none unless @account.feature_enabled?('help_center')

    portal = public_portal
    return Article.none unless portal

    scope = Article.where(account_id: @account.id, portal_id: portal.id, locale: portal.public_locale_codes).published
    scope = scope.text_search(query.strip) if query.strip.present?
    scope.order(updated_at: :desc, id: :desc).limit(25)
  end

  private

  def public_portal
    portal = @identity.inbox.portal
    portal if portal && portal.account_id == @account.id && !portal.archived?
  end

  def tickets_with_access(scope)
    scope.where('jrc_service_desk_services.portal_access_until IS NULL OR jrc_service_desk_services.portal_access_until > ?', Time.current)
         .where("jrc_service_desk_ticket_statuses.phase IN ('open','waiting') OR " \
                'jrc_service_desk_services.portal_history_days IS NULL OR jrc_service_desk_tickets.updated_at >= ' \
                "?::timestamp - jrc_service_desk_services.portal_history_days * INTERVAL '1 day'", Time.current)
         .where(company_restriction, @contact.company_id.present?, [@contact.company_id].compact.to_json)
         .where(contract_restriction)
  end

  def company_restriction
    'jrc_service_desk_services.allowed_company_ids IS NULL OR ' \
      "jrc_service_desk_services.allowed_company_ids = '[]'::jsonb " \
      'OR (? AND jrc_service_desk_services.allowed_company_ids @> ?::jsonb)'
  end

  def contract_restriction
    'jrc_service_desk_services.allowed_contract_ids IS NULL OR ' \
      "jrc_service_desk_services.allowed_contract_ids = '[]'::jsonb " \
      'OR jrc_service_desk_services.allowed_contract_ids @> jsonb_build_array(jrc_service_desk_tickets.contract_id)'
  end
end
