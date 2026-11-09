# frozen_string_literal: true

# A persisted hmac_verified flag survives native contact merges. Portal access
# additionally proves the contact's current identifier against this widget on
# every request. The proof is never part of a ticket or response payload.
class JrcServiceDesk::PortalIdentityProof
  IDENTIFIER_HEADER = 'X-Service-Desk-Identifier'
  TOKEN_HEADER = 'X-Service-Desk-Identity-Token'

  def initialize(identifier:, token:)
    @identifier = identifier
    @token = token
  end

  def verify!(identity:)
    current_identifier = identity.contact.identifier
    widget = identity.inbox.channel
    valid = widget.is_a?(Channel::WebWidget) && identifier_matches?(current_identifier) && token_format_valid?
    raise JrcServiceDesk::PortalIdentityRequired unless valid

    expected = OpenSSL::HMAC.hexdigest('sha256', widget.hmac_token, current_identifier)
    raise JrcServiceDesk::PortalIdentityRequired unless ActiveSupport::SecurityUtils.secure_compare(@token, expected)

    true
  end

  def establishment_ids(identity:)
    verify!(identity: identity)
    JrcServiceDesk::PortalGrant.where(account_id: identity.contact.account_id, contact_id: identity.contact_id,
                                     contact_inbox_id: identity.id, active: true).lock('FOR SHARE').includes(:user).select do |grant|
      grant.available? && grant.user.active_for_authentication?
    end.flat_map(&:establishment_ids).uniq
  end

  private

  def identifier_matches?(current_identifier)
    current_identifier.is_a?(String) && current_identifier.present? && @identifier.is_a?(String) && @identifier == current_identifier
  end

  def token_format_valid?
    @token.is_a?(String) && /\A[0-9a-f]{64}\z/.match?(@token)
  end
end
