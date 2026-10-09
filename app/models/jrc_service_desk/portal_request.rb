# frozen_string_literal: true

class JrcServiceDesk::PortalRequest < JrcServiceDesk::UnitRecord
  include JrcServiceDesk::AppendOnly
  %i[service ticket execution_membership].each do |name|
    belongs_to name, class_name: "JrcServiceDesk::#{name == :execution_membership ? 'UnitMembership' : name.to_s.camelize}"
  end
  %i[contact contact_inbox inbox conversation message].each { |name| belongs_to name, class_name: "::#{name.to_s.camelize}" }
  validates :request_key, presence: true, length: { maximum: 120 }, uniqueness: { scope: %i[account_id contact_id] }
  validates :fingerprint, :service_revision, format: { with: /\A[a-f0-9]{64}\z/ }
  validate :verified_provenance

  private

  def verified_provenance
    %i[service ticket execution_membership].each { |name| validate_unit_reference(name) }
    %i[contact inbox conversation message].each { |name| validate_account_reference(name) }
    return if identity_matches? && incoming_message_matches?

    errors.add(:contact_inbox, 'must bind the actual native customer, conversation and incoming message')
  end

  def identity_matches?
    contact_inbox && contact_inbox.contact_id == contact_id && contact_inbox.inbox_id == inbox_id &&
      conversation&.contact_inbox_id == contact_inbox_id && ticket&.requester_id == contact_id
  end

  def incoming_message_matches?
    message&.conversation_id == conversation_id && message&.sender == contact && message&.incoming?
  end
end
