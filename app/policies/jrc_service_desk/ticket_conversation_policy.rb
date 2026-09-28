# frozen_string_literal: true

class JrcServiceDesk::TicketConversationPolicy < JrcServiceDesk::TicketRecordPolicy
  def index?
    false
  end

  def show?
    super && conversation_allowed?
  end

  def create?
    record_unit_allowed? && parent_policy.link_conversation? && conversation_allowed?
  end

  private

  def conversation_allowed?
    conversation = record.conversation
    context = operational_context
    conversation && context.record_in_account?(conversation) &&
      Pundit.policy!(context.to_h, conversation).show?
  end

  # Native ConversationPolicy has no equivalent SQL row-scope for all channel rules.
  # Do not broaden it or return links unchecked: list exposure is deliberately denied.
  class Scope < JrcServiceDesk::TicketRecordPolicy::Scope
    def resolve
      scope.none
    end
  end
end
