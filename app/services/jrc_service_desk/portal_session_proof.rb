# frozen_string_literal: true

# Native User credentials are validated by DeviseTokenAuth before constructing
# this adapter. Grants bind the exact ContactInbox and cannot follow a CRM merge.
class JrcServiceDesk::PortalSessionProof
  def initialize(grant:, user:, additional_contact: false)
    @grant = grant
    @user = user
    @additional_contact = additional_contact
  end

  def verify!(identity:)
    @grant.reload
    allowed = @grant.user_id == @user.id && @user.active_for_authentication? && @grant.available?
    allowed &&= identity.inbox_id == @grant.inbox_id && identity.contact.account_id == @grant.account_id &&
                identity.contact.company_id == @grant.company_id && !identity.contact.blocked?
    allowed &&= if @additional_contact
                  @grant.role != 'requester' && @grant.visible_contact_ids.include?(identity.contact_id)
                else
                  identity.id == @grant.contact_inbox_id && identity.contact_id == @grant.contact_id
                end
    raise JrcServiceDesk::PortalIdentityRequired unless allowed

    true
  end
end
