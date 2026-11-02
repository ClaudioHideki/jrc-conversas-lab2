# frozen_string_literal: true

class JrcServiceDesk::RequesterPortalScope < JrcServiceDesk::PortalScope
  def initialize(grant:, user:)
    @grant = grant
    @portal_user = user
    super(contact_inbox: grant.contact_inbox, identity_proof: JrcServiceDesk::PortalSessionProof.new(grant: grant, user: user))
  end

  def tickets
    scopes = [super.where(company_id: @grant.company_id)]
    additional_scopes.each { |scope| scopes << scope.tickets.where(company_id: @grant.company_id) }
    scopes.reduce { |result, scope| result.or(scope) }
  end

  def conversations
    scopes = [super]
    additional_scopes.each { |scope| scopes << scope.conversations }
    scopes.reduce { |result, scope| result.or(scope) }
  end

  private

  def additional_scopes
    return [] if @grant.role == 'requester'

    @additional_scopes ||= ContactInbox.where(inbox_id: @grant.inbox_id, hmac_verified: true, contact_id: @grant.visible_contact_ids)
                                      .includes(:contact).filter_map do |identity|
      proof = JrcServiceDesk::PortalSessionProof.new(grant: @grant, user: @portal_user, additional_contact: true)
      JrcServiceDesk::PortalScope.new(contact_inbox: identity, identity_proof: proof)
    rescue JrcServiceDesk::PortalIdentityRequired, Pundit::NotAuthorizedError
      nil
    end
  end
end
