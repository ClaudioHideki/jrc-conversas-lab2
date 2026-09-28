# frozen_string_literal: true

class JrcServiceDesk::TicketConversation < JrcServiceDesk::TicketRecord
  include JrcServiceDesk::AppendOnly

  belongs_to :conversation, class_name: '::Conversation', optional: false
  belongs_to :linked_by_membership, class_name: 'JrcServiceDesk::UnitMembership', optional: false

  validates :conversation_id, uniqueness: { scope: %i[account_id unit_id ticket_id] }
  validate :conversation_and_actor_are_consistent

  private

  def conversation_and_actor_are_consistent
    validate_account_reference(:conversation)
    validate_unit_reference(:linked_by_membership)
    validate_active_reference(:linked_by_membership)
  end
end
